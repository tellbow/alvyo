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

	mu     sync.Mutex
	jobs   map[string]*job
	latest map[string]string // the newest key asked for, by prefix
	sem    chan struct{}
}

type job struct {
	done, total int
	failed      bool
}

// maxBuilds run at the same time; more wait.
const maxBuilds = 2

// buildTimeout bounds a build once it runs: the biggest pack (MaxTiles in
// both layers) at the tile cache's pace of 40 tiles a second takes 50
// minutes.
const buildTimeout = 90 * time.Minute

// inUse: packs used this recently are not pruned (being downloaded, or
// just built).
const inUse = 10 * time.Minute

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
		s.latest = map[string]string{}
		s.sem = make(chan struct{}, maxBuilds)
	}
	s.latest[prefix] = key
	if j := s.jobs[key]; j != nil && !j.failed {
		s.mu.Unlock()
		return s.Status(key)
	}
	j := &job{}
	s.jobs[key] = j
	s.mu.Unlock()

	go func() {
		s.sem <- struct{}{}
		defer func() { <-s.sem }()
		ctx, cancel := context.WithTimeout(context.Background(), buildTimeout) // from when it runs
		defer cancel()
		err := func() error {
			ts, err := tiles(ctx)
			if err != nil {
				return err
			}
			_, err = s.Builder.Build(ctx, key, ts, func(done, total int) {
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
		// Older versions go, unless a newer one was asked for meanwhile
		// (this build is then the old one).
		if s.latest[prefix] == key {
			s.Builder.RemoveOthers(key, prefix)
		}
		go s.Prune() // keep within MaxBytes between the regular runs
	}()
	return Status{State: "building", Key: key}
}

// Prune deletes packs not used for MaxAge, then the least recently used
// until all packs together take at most MaxBytes. A pack's files go
// together; downloads count as use (Touch). Packs used in the last minutes
// and builds under way stay; what a crashed build left behind goes.
func (s *Service) Prune() {
	entries, err := os.ReadDir(s.Builder.Dir)
	if err != nil {
		return
	}
	type pack struct {
		paths []string
		size  int64
		used  time.Time
	}
	packs := map[string]*pack{}
	for _, e := range entries {
		info, err := e.Info()
		if err != nil || e.IsDir() {
			continue
		}
		p := filepath.Join(s.Builder.Dir, e.Name())
		if building(e.Name()) {
			if time.Since(info.ModTime()) > buildTimeout {
				_ = os.Remove(p)
			}
			continue
		}
		k := packOf(e.Name())
		if packs[k] == nil {
			packs[k] = &pack{}
		}
		pk := packs[k]
		pk.paths = append(pk.paths, p)
		pk.size += info.Size()
		if info.ModTime().After(pk.used) {
			pk.used = info.ModTime()
		}
	}
	remove := func(pk *pack) {
		for _, p := range pk.paths {
			_ = os.Remove(p)
		}
	}
	var kept []*pack
	var total int64
	for _, pk := range packs {
		if s.MaxAge > 0 && time.Since(pk.used) > s.MaxAge {
			remove(pk)
			continue
		}
		kept = append(kept, pk)
		total += pk.size
	}
	sort.Slice(kept, func(i, j int) bool { return kept[i].used.Before(kept[j].used) })
	for _, pk := range kept {
		if s.MaxBytes == 0 || total <= s.MaxBytes || time.Since(pk.used) < inUse {
			break
		}
		remove(pk)
		total -= pk.size
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
