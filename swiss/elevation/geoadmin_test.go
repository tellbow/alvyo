package elevation

import (
	"context"
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/tellbow/alvyo/swiss/geo"
	"github.com/tellbow/alvyo/swiss/lv95"
)

// fakeProfile mimics profile.json: it returns every input vertex with its
// planar distance and a height from terrain(e, n).
func fakeProfile(t *testing.T, terrain func(e, n float64) *float64) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Errorf("method %s", r.Method)
		}
		q := r.URL.Query()
		if q.Get("sr") != "2056" || q.Get("distinct_points") != "true" || q.Get("nb_points") == "" {
			t.Errorf("query %v", q)
		}
		var body struct {
			Type        string       `json:"type"`
			Coordinates [][2]float64 `json:"coordinates"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Type != "LineString" {
			t.Fatalf("body: %v %+v", err, body)
		}
		type alts struct {
			COMB *float64 `json:"COMB"`
		}
		type point struct {
			Dist float64 `json:"dist"`
			Alts alts    `json:"alts"`
		}
		var out []point
		d := 0.0
		for i, c := range body.Coordinates {
			if i > 0 {
				p := body.Coordinates[i-1]
				d += math.Hypot(c[0]-p[0], c[1]-p[1])
			}
			out = append(out, point{Dist: math.Round(d*10) / 10, Alts: alts{COMB: terrain(c[0], c[1])}})
		}
		if d == 0 {
			// As the service: a line without length is none.
			http.Error(w, `{"error":{"code":400,"message":"Invalid LineString"},"success":false}`, http.StatusBadRequest)
			return
		}
		_ = json.NewEncoder(w).Encode(out)
	}
}

// slope is a plane rising 1 m per 100 m eastwards from 1000 m at E 2 700 000.
func slope(e, _ float64) *float64 { h := 1000 + (e-2700000)/100; return &h }

func line(n int) []geo.Point {
	pts := make([]geo.Point, n)
	for i := range pts {
		pts[i] = geo.Point{Lon: 8.0 + float64(i)*0.001, Lat: 46.5}
	}
	return pts
}

func expected(p geo.Point) float64 {
	e, n := lv95.FromWGS84(p.Lon, p.Lat)
	return *slope(e, n)
}

func TestSample(t *testing.T) {
	srv := httptest.NewServer(fakeProfile(t, slope))
	defer srv.Close()
	g := &GeoAdmin{BaseURL: srv.URL}

	pts := line(20)
	h, err := g.Sample(context.Background(), pts)
	if err != nil {
		t.Fatal(err)
	}
	for i, p := range pts {
		if math.Abs(h[i]-expected(p)) > 0.05 {
			t.Errorf("point %d: %.2f, want %.2f", i, h[i], expected(p))
		}
	}
}

func TestSampleChunks(t *testing.T) {
	var calls atomic.Int32
	fake := fakeProfile(t, slope)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		fake(w, r)
	}))
	defer srv.Close()
	g := &GeoAdmin{BaseURL: srv.URL, chunkSize: 3}

	pts := line(7) // chunks [0..2] [2..4] [4..6]
	h, err := g.Sample(context.Background(), pts)
	if err != nil {
		t.Fatal(err)
	}
	if calls.Load() != 3 {
		t.Errorf("%d requests, want 3", calls.Load())
	}
	for i, p := range pts {
		if math.Abs(h[i]-expected(p)) > 0.05 {
			t.Errorf("point %d: %.2f, want %.2f", i, h[i], expected(p))
		}
	}
}

func TestSampleFillsGaps(t *testing.T) {
	// The third vertex has no height; it must be interpolated from neighbours.
	pts := line(5)
	e2, _ := lv95.FromWGS84(pts[2].Lon, pts[2].Lat)
	gap := func(e, n float64) *float64 {
		if math.Abs(e-e2) < 1 {
			return nil
		}
		return slope(e, n)
	}
	srv := httptest.NewServer(fakeProfile(t, gap))
	defer srv.Close()

	h, err := (&GeoAdmin{BaseURL: srv.URL}).Sample(context.Background(), pts)
	if err != nil {
		t.Fatal(err)
	}
	if math.Abs(h[2]-expected(pts[2])) > 0.05 {
		t.Errorf("gap filled with %.2f, want %.2f", h[2], expected(pts[2]))
	}
}

func TestSampleNoCoverage(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("[]"))
	}))
	defer srv.Close()
	_, err := (&GeoAdmin{BaseURL: srv.URL}).Sample(context.Background(), line(3))
	if !errors.Is(err, ErrNoCoverage) {
		t.Errorf("err = %v, want ErrNoCoverage", err)
	}
}

func TestSampleRetries(t *testing.T) {
	var calls atomic.Int32
	fake := fakeProfile(t, slope)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if calls.Add(1) == 1 {
			http.Error(w, "busy", http.StatusServiceUnavailable)
			return
		}
		fake(w, r)
	}))
	defer srv.Close()
	if _, err := (&GeoAdmin{BaseURL: srv.URL, retryBase: time.Millisecond}).Sample(context.Background(), line(3)); err != nil {
		t.Fatalf("after retry: %v", err)
	}
	if calls.Load() != 2 {
		t.Errorf("%d calls, want 2", calls.Load())
	}
}

func TestRetryWait(t *testing.T) {
	for n, from := range map[int]time.Duration{1: time.Second, 2: 2 * time.Second, 3: 4 * time.Second, 7: 64 * time.Second, 9: 64 * time.Second} {
		seen := map[time.Duration]bool{}
		for range 20 {
			w := retryWait(n, 0)
			if w < from || w >= from+time.Second {
				t.Errorf("retry %d: %v, want %v plus less than 1 s", n, w, from)
			}
			seen[w] = true
		}
		if len(seen) < 2 {
			t.Errorf("retry %d: always the same wait %v, want jitter", n, seen)
		}
	}
}

func TestSampleAccepts203(t *testing.T) {
	fake := fakeProfile(t, slope)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNonAuthoritativeInfo) // seen from geo.admin's cache
		fake(w, r)
	}))
	defer srv.Close()
	if _, err := (&GeoAdmin{BaseURL: srv.URL}).Sample(context.Background(), line(3)); err != nil {
		t.Errorf("203 response rejected: %v", err)
	}
}

func TestSampleNoRetryOnClientError(t *testing.T) {
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls.Add(1)
		http.Error(w, `{"error":"too many points"}`, http.StatusRequestEntityTooLarge)
	}))
	defer srv.Close()
	if _, err := (&GeoAdmin{BaseURL: srv.URL}).Sample(context.Background(), line(3)); err == nil {
		t.Fatal("want error")
	}
	if calls.Load() != 1 {
		t.Errorf("%d calls, want 1 (no retry on 4xx)", calls.Load())
	}
}

func TestSampleSinglePoint(t *testing.T) {
	srv := httptest.NewServer(fakeProfile(t, slope))
	defer srv.Close()
	pts := line(1)
	h, err := (&GeoAdmin{BaseURL: srv.URL}).Sample(context.Background(), pts)
	if err != nil || len(h) != 1 || math.Abs(h[0]-expected(pts[0])) > 0.05 {
		t.Errorf("single point: %v %v", h, err)
	}
}

// A leg without length (both ends snapped to the same spot, or a few
// centimetres apart) still gets its height.
func TestSampleWithoutLength(t *testing.T) {
	srv := httptest.NewServer(fakeProfile(t, slope))
	defer srv.Close()
	g := &GeoAdmin{BaseURL: srv.URL}
	p := geo.Point{Lon: 8.0, Lat: 46.5}
	for _, pts := range [][]geo.Point{{p}, {p, p}, {p, {Lon: p.Lon + 0.0000005, Lat: p.Lat}}} {
		h, err := g.Sample(context.Background(), pts)
		if err != nil {
			t.Fatalf("%d points: %v", len(pts), err)
		}
		for i := range pts {
			if math.Abs(h[i]-expected(p)) > 0.05 {
				t.Errorf("%d points: %.2f, want %.2f", len(pts), h[i], expected(p))
			}
		}
	}
}
