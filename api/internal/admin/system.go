package admin

import (
	"context"
	"encoding/json"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// Probe is an outside service the admin portal checks: an HTTP address
// (up when it answers below 500) or tcp://host:port (up when it accepts).
type Probe struct {
	Name, URL string
}

// Service is a probe's answer.
type Service struct {
	Name   string `json:"name"`
	Up     bool   `json:"up"`
	Ms     int    `json:"ms" doc:"How long it took to answer"`
	Detail string `json:"detail,omitempty" doc:"Why it is down"`
}

// probeTimeout bounds each check; all run at once.
const probeTimeout = 3 * time.Second

// Services checks the probes, in their order.
func Services(ctx context.Context, probes []Probe) []Service {
	out := make([]Service, len(probes))
	var wg sync.WaitGroup
	for i, p := range probes {
		wg.Go(func() {
			ctx, cancel := context.WithTimeout(ctx, probeTimeout)
			defer cancel()
			start := time.Now()
			err := check(ctx, p.URL)
			out[i] = Service{Name: p.Name, Up: err == nil, Ms: int(time.Since(start).Milliseconds())}
			if err != nil {
				out[i].Detail = err.Error()
			}
		})
	}
	wg.Wait()
	return out
}

func check(ctx context.Context, url string) error {
	if addr, ok := strings.CutPrefix(url, "tcp://"); ok {
		c, err := (&net.Dialer{}).DialContext(ctx, "tcp", addr)
		if err == nil {
			_ = c.Close()
		}
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "alvyo-admin (+https://github.com/tellbow/alvyo)")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	_ = resp.Body.Close()
	if resp.StatusCode >= 500 {
		return &statusError{resp.Status}
	}
	return nil
}

type statusError struct{ status string }

func (e *statusError) Error() string { return "answered " + e.status }

// DataSet is data a job keeps, and how fresh it is.
type DataSet struct {
	Name  string     `json:"name"`
	At    *time.Time `json:"at,omitempty" doc:"When it was last loaded or is for"`
	Count *int64     `json:"count,omitempty"`
	Stale bool       `json:"stale" doc:"Older than its job's schedule allows"`
	Note  string     `json:"note,omitempty"`
}

// System is what the admin portal shows of the data and the database.
type System struct {
	Data      []DataSet `json:"data"`
	Migration int64     `json:"migration" doc:"The database's last migration"`
}

// SystemInfo reads how fresh the jobs' data is.
func (s *Store) SystemInfo(ctx context.Context) (System, error) {
	var sys System
	var radar, snow, wanderland *time.Time
	var routes, trails, places, pois int64
	err := s.DB.QueryRow(ctx, `SELECT
			(SELECT max(created_at) FROM precip_frames),
			(SELECT max(day)::timestamptz FROM snow_days),
			(SELECT max(imported_at) FROM wanderland_import),
			(SELECT count(*) FROM wanderland_routes),
			(SELECT count(*) FROM tlm_hiking_paths),
			(SELECT count(*) FROM places),
			(SELECT count(*) FROM pois),
			(SELECT coalesce(max(version_id), 0) FROM goose_db_version)`).
		Scan(&radar, &snow, &wanderland, &routes, &trails, &places, &pois, &sys.Migration)
	if err != nil {
		return sys, err
	}
	// Stale: older than the job's schedule and some slack.
	stale := func(at *time.Time, limit time.Duration) bool { return at == nil || time.Since(*at) > limit }
	day := 24 * time.Hour
	sys.Data = []DataSet{
		{Name: "Regenradar (weather-precip, alle 5 Minuten)", At: radar, Stale: stale(radar, time.Hour)},
		{Name: "Schneedecke (snow-cover, alle 6 Stunden)", At: snow, Stale: stale(snow, 3*day)},
		{Name: "Wanderland-Routen (wanderland-import, monatlich)", At: wanderland, Count: &routes, Stale: stale(wanderland, 40*day)},
	}
	graph := DataSet{Name: "Routing-Graph (graph-refresh, wöchentlich)"}
	if at, err := graphDate(ctx, s.GraphHopper); err == nil {
		graph.At, graph.Stale = &at, stale(&at, 9*day)
	} else {
		graph.Stale, graph.Note = true, err.Error()
	}
	sys.Data = append(sys.Data, graph)
	alti := DataSet{Name: "swissALTI3D (alti-import, monatlich)"}
	if s.AltiDir == "" {
		alti.Note = "nicht eingerichtet: Höhen von geo.admin"
	} else if at, n, err := newestFile(s.AltiDir); err == nil {
		alti.At, alti.Count, alti.Stale = &at, &n, stale(&at, 40*day)
	} else {
		alti.Stale, alti.Note = true, err.Error()
	}
	sys.Data = append(sys.Data, alti,
		DataSet{Name: "Wanderwege (tlm-import, von Hand)", Count: &trails, Stale: trails == 0},
		DataSet{Name: "Haltestellen und Orte (places-import, von Hand)", Count: &places, Stale: places == 0},
		DataSet{Name: "Punkte unterwegs (graph-refresh)", Count: &pois, Stale: pois == 0},
	)
	return sys, nil
}

// graphDate is when the OSM data of GraphHopper's graph was taken.
func graphDate(ctx context.Context, base string) (time.Time, error) {
	ctx, cancel := context.WithTimeout(ctx, probeTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, strings.TrimSuffix(base, "/")+"/info", nil)
	if err != nil {
		return time.Time{}, err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return time.Time{}, err
	}
	defer func() { _ = resp.Body.Close() }()
	var info struct {
		DataDate time.Time `json:"data_date"`
	}
	err = json.NewDecoder(resp.Body).Decode(&info)
	return info.DataDate, err
}

// newestFile is the newest tile's time and the number of tiles in dir.
func newestFile(dir string) (time.Time, int64, error) {
	var newest time.Time
	var n int64
	err := filepath.WalkDir(dir, func(_ string, e os.DirEntry, err error) error {
		if err != nil || e.IsDir() {
			return err
		}
		n++
		if info, err := e.Info(); err == nil && info.ModTime().After(newest) {
			newest = info.ModTime()
		}
		return nil
	})
	return newest, n, err
}
