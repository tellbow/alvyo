package areas

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"sync/atomic"
	"testing"
	"time"

	"github.com/tellbow/odysgeh/api/internal/testdb"
	"github.com/tellbow/odysgeh/swiss/geo"
)

// identifyServer answers with the recorded answer for a line near
// Grindelwald First, or fails while broken.
func identifyServer(t *testing.T, broken *atomic.Bool) (*httptest.Server, *atomic.Int32) {
	body, err := os.ReadFile("testdata/identify_grindelwald.json")
	if err != nil {
		t.Fatal(err)
	}
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		q := r.URL.Query()
		if q.Get("geometryType") != "esriGeometryPolyline" || q.Get("mapExtent") == "" || q.Get("imageDisplay") == "" {
			t.Errorf("request %s", r.URL.RawQuery)
		}
		if broken != nil && broken.Load() {
			w.WriteHeader(http.StatusBadGateway)
			return
		}
		_, _ = w.Write(body)
	}))
	t.Cleanup(srv.Close)
	return srv, &calls
}

// east is a line of n points 100 m apart zigzagging east from 8.0, 46.66
// (the zigzag keeps simplification from dropping points).
func east(n int) []geo.Point {
	pts := make([]geo.Point, n)
	for i := range pts {
		pts[i] = geo.Point{Lon: 8.0 + float64(i)*0.0013, Lat: 46.66 + float64(i%2)*0.0003}
	}
	return pts
}

func TestCrossed(t *testing.T) {
	ctx := context.Background()
	srv, calls := identifyServer(t, nil)
	f := &Finder{DB: testdb.New(t), URL: srv.URL}

	areas, err := f.Crossed(ctx, east(10))
	if err != nil {
		t.Fatal(err)
	}
	if len(areas) != 3 {
		t.Fatalf("%d areas: %+v", len(areas), areas)
	}
	first := areas[0]
	if first.Kind != "wildlife_rest" || first.Name != "Grindelwald Firstweng-Luegenweid (Nr. 3.00)" || !first.Binding ||
		first.Rule.De != "Zutrittsverbot" || first.Rule.Fr == "" || first.Period == nil ||
		*first.Period != (Period{From: "12-01", To: "04-20"}) || first.Link == "" {
		t.Errorf("rest area %+v", first)
	}
	if last := areas[2]; last.Kind != "hunting_reserve" || last.Name != "Schwarzhorn" || !last.Binding ||
		last.Rule.En != "Area with partial protection regulations" || last.Period != nil {
		t.Errorf("hunting reserve %+v", last)
	}

	// The same line again: from the cache.
	before := calls.Load()
	if _, err := f.Crossed(ctx, east(10)); err != nil || calls.Load() != before {
		t.Errorf("not cached: %v, %d more calls", err, calls.Load()-before)
	}

	// A long line in chunks of 200 points sharing one: 450 → 3 requests;
	// areas found in several chunks come once.
	before = calls.Load()
	areas, err = f.Crossed(ctx, east(450))
	if err != nil || calls.Load()-before != 3 || len(areas) != 3 {
		t.Errorf("long line: %v, %d calls, %d areas", err, calls.Load()-before, len(areas))
	}
}

func TestCrossedUnavailable(t *testing.T) {
	var broken atomic.Bool
	broken.Store(true)
	srv, _ := identifyServer(t, &broken)
	f := &Finder{DB: testdb.New(t), URL: srv.URL}
	if _, err := f.Crossed(context.Background(), east(5)); !errors.Is(err, ErrUnavailable) {
		t.Errorf("err = %v", err)
	}
	// Nothing cached from a failure.
	broken.Store(false)
	if areas, err := f.Crossed(context.Background(), east(5)); err != nil || len(areas) != 3 {
		t.Errorf("after recovery: %v %d", err, len(areas))
	}
}

func TestPeriod(t *testing.T) {
	for _, tc := range []struct {
		in   string
		want *Period
	}{
		{"01.12. - 20.04.", &Period{"12-01", "04-20"}},
		{"15.11.-31.3.", &Period{"11-15", "03-31"}},
		{"01.01. - 31.12.", nil},
		{"", nil},
		{"ganzjährig", nil},
	} {
		got := parsePeriod(tc.in)
		if (got == nil) != (tc.want == nil) || (got != nil && *got != *tc.want) {
			t.Errorf("%q: %+v, want %+v", tc.in, got, tc.want)
		}
	}
	winter := Period{From: "12-01", To: "04-20"}
	for day, want := range map[string]bool{"2026-12-01": true, "2027-01-15": true, "2027-04-20": true, "2027-04-21": false, "2026-08-01": false} {
		d, _ := time.Parse(time.DateOnly, day)
		if winter.Contains(d) != want {
			t.Errorf("%s in winter: %v", day, !want)
		}
	}
}
