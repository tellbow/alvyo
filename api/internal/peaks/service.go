package peaks

import (
	"context"
	"errors"
	"fmt"
	"image"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/image/webp"
)

// MaxAge is how long a pack is kept before it is built anew (summits change
// with the weekly places import).
const MaxAge = 7 * 24 * time.Hour

// ErrBuilding is returned while the pack is being built.
var ErrBuilding = errors.New("the pack is being built")

// Service builds the pack once in the background and keeps it in Dir.
type Service struct {
	DB       *pgxpool.Pool
	TilesURL string // our tile cache, with Mapterhorn's terrain under /tiles/terrain/
	Dir      string
	Client   *http.Client
	Tile     TileFunc // nil: from TilesURL

	mu       sync.Mutex
	building bool
	failed   error
}

func (s *Service) path() string {
	return filepath.Join(s.Dir, fmt.Sprintf("peaks-v%d.bin.gz", Version))
}

// File returns the pack's path and when it was built, starting a build when
// there is none or it is old: ErrBuilding until one is there.
func (s *Service) File() (string, time.Time, error) {
	info, err := os.Stat(s.path())
	if err == nil && time.Since(info.ModTime()) > MaxAge {
		s.Start() // the old one is served meanwhile
	}
	if err == nil {
		return s.path(), info.ModTime(), nil
	}
	s.Start()
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.failed != nil {
		return "", time.Time{}, s.failed
	}
	return "", time.Time{}, ErrBuilding
}

// Start builds the pack in the background unless a build is running.
func (s *Service) Start() {
	s.mu.Lock()
	if s.building {
		s.mu.Unlock()
		return
	}
	s.building, s.failed = true, nil
	s.mu.Unlock()
	go func() {
		start := time.Now()
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Minute)
		defer cancel()
		err := s.build(ctx)
		s.mu.Lock()
		s.building, s.failed = false, err
		s.mu.Unlock()
		if err != nil {
			slog.Error("peaks: build failed", "err", err)
			return
		}
		slog.Info("peaks: pack built", "took", time.Since(start).Round(time.Second).String())
	}()
}

func (s *Service) build(ctx context.Context) error {
	peaks, err := s.peaks(ctx)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(s.Dir, 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(s.Dir, "peaks-*.tmp")
	if err != nil {
		return err
	}
	defer func() { _ = os.Remove(tmp.Name()) }()
	tile := s.Tile
	if tile == nil {
		tile = s.fetch
	}
	if err := Write(ctx, tmp, tile, peaks); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), s.path())
}

// peaks returns the named summits with a height.
func (s *Service) peaks(ctx context.Context) ([]Peak, error) {
	rows, err := s.DB.Query(ctx, `SELECT name, ele, ST_X(geom), ST_Y(geom) FROM pois
		WHERE kind = 'peak' AND name <> '' AND ele IS NOT NULL ORDER BY ele DESC`)
	if err != nil {
		return nil, fmt.Errorf("peaks: summits: %w", err)
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (Peak, error) {
		var p Peak
		err := r.Scan(&p.Name, &p.Ele, &p.Lon, &p.Lat)
		return p, err
	})
}

// fetch gets a terrain tile through the tile cache.
func (s *Service) fetch(ctx context.Context, x, y int) (image.Image, error) {
	client := s.Client
	if client == nil {
		// One hung tile would hold up the whole build.
		client = &http.Client{Timeout: 30 * time.Second}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, fmt.Sprintf("%s/tiles/terrain/%d/%d/%d.webp", s.TilesURL, zoom, x, y), nil)
	if err != nil {
		return nil, err
	}
	res, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer func() { _ = res.Body.Close() }()
	if res.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("status %s", res.Status)
	}
	return webp.Decode(res.Body)
}
