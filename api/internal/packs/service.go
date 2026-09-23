package packs

import (
	"context"
	"log/slog"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

// Status of a pack for the app.
type Status struct {
	State string `json:"state" enum:"missing,building,ready,failed"`
	Key   string `json:"key" doc:"Changes when the route or journey changes: a saved pack with another key is out of date"`
	Done  int    `json:"done" doc:"Tiles fetched so far while building"`
	Total int    `json:"total"`
	Files []File `json:"files,omitempty"`
}

// Service builds packs in the background, a few at a time.
type Service struct {
	Builder *Builder
	// Prune deletes packs not used for MaxAge, then the oldest until all
	// take at most MaxBytes; zero: no limit.
	MaxAge   time.Duration
	MaxBytes int64

	mu   sync.Mutex
	jobs map[string]*job
	sem  chan struct{}
}

type job struct {
	done, total int
	failed      bool
}

// maxBuilds run at the same time; more wait.
const maxBuilds = 2

// Status reports the pack under key.
func (s *Service) Status(key string) Status {
	if files, ok := s.Builder.Existing(key); ok {
		return Status{State: "ready", Key: key, Files: files}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	switch j := s.jobs[key]; {
	case j == nil:
		return Status{State: "missing", Key: key}
	case j.failed:
		return Status{State: "failed", Key: key}
	default:
		return Status{State: "building", Key: key, Done: j.done, Total: j.total}
	}
}

// Ensure starts building the pack under key unless it exists or is being
// built. tiles is called in the background.
func (s *Service) Ensure(key, prefix string, tiles func(context.Context) ([]Tile, error)) Status {
	if st := s.Status(key); st.State == "ready" || st.State == "building" {
		return st
	}
	s.mu.Lock()
	if s.jobs == nil {
		s.jobs = map[string]*job{}
		s.sem = make(chan struct{}, maxBuilds)
	}
	if j := s.jobs[key]; j != nil && !j.failed {
		s.mu.Unlock()
		return s.Status(key)
	}
	j := &job{}
	s.jobs[key] = j
	s.mu.Unlock()

	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
		defer cancel()
		s.sem <- struct{}{}
		defer func() { <-s.sem }()
		err := func() error {
			ts, err := tiles(ctx)
			if err != nil {
				return err
			}
			_, err = s.Builder.Build(ctx, key, prefix, ts, func(done, total int) {
				s.mu.Lock()
				j.done, j.total = done, total
				s.mu.Unlock()
			})
			return err
		}()
		s.mu.Lock()
		defer s.mu.Unlock()
		if err != nil {
			slog.Error("building offline pack", "pack", key, "err", err)
			j.failed = true
			return
		}
		delete(s.jobs, key)
		go s.Prune() // keep within MaxBytes between the regular runs
	}()
	return Status{State: "building", Key: key}
}

// Prune deletes packs not used for MaxAge, then the oldest ones until all
// packs together take at most MaxBytes. Downloads count as use.
func (s *Service) Prune() {
	entries, err := os.ReadDir(s.Builder.Dir)
	if err != nil {
		return
	}
	type file struct {
		path string
		size int64
		used time.Time
	}
	var files []file
	var total int64
	for _, e := range entries {
		info, err := e.Info()
		if err != nil || e.IsDir() {
			continue
		}
		p := filepath.Join(s.Builder.Dir, e.Name())
		if s.MaxAge > 0 && time.Since(info.ModTime()) > s.MaxAge {
			_ = os.Remove(p)
			continue
		}
		files = append(files, file{p, info.Size(), info.ModTime()})
		total += info.Size()
	}
	sort.Slice(files, func(i, j int) bool { return files[i].used.Before(files[j].used) })
	for _, f := range files {
		if s.MaxBytes == 0 || total <= s.MaxBytes {
			break
		}
		_ = os.Remove(f.path)
		total -= f.size
	}
}

// PruneEvery runs Prune until ctx ends.
func (s *Service) PruneEvery(ctx context.Context, every time.Duration) {
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		s.Prune()
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}
