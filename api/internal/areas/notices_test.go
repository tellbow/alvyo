package areas

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/tellbow/alvyo/api/internal/testdb"
	"github.com/tellbow/alvyo/swiss/geo"
)

func TestNotices(t *testing.T) {
	body, err := os.ReadFile("testdata/identify_notices.json")
	if err != nil {
		t.Fatal(err)
	}
	calls := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		if q := r.URL.Query(); q.Get("returnGeometry") != "true" || q.Get("geometryFormat") != "geojson" {
			t.Errorf("request %s", r.URL.RawQuery)
		}
		_, _ = w.Write(body)
	}))
	t.Cleanup(srv.Close)
	f := &Finder{DB: testdb.New(t), URL: srv.URL}
	line := []geo.Point{{Lon: 8.0, Lat: 46.66}, {Lon: 8.02, Lat: 46.66}}
	today := time.Date(2026, 9, 28, 10, 0, 0, 0, time.UTC)

	got, _, err := f.Notices(context.Background(), line, today)
	if err != nil {
		t.Fatal(err)
	}
	// Not the closure only crossed, the way round, or one over already.
	if len(got) != 2 || got[0].Kind != "closure" || got[1].Kind != "shooting" {
		t.Fatalf("notices: %+v", got)
	}
	c, s := got[0], got[1]
	if c.Title.De != "Along the line" || c.Reason == nil || c.Reason.Fr != "Chutes de pierres" || c.From != "2026-09-01" || c.To != "2026-10-31" {
		t.Errorf("closure: %+v", c)
	}
	if s.Title.De != "Geissalp" || s.Link == nil || s.Phone == "" || len(s.Days) != 2 ||
		s.Days[0] != (ShootingDay{Date: "2026-09-28"}) || s.Days[1].Date != "2026-09-29" {
		t.Errorf("shooting, from today on: %+v", s)
	}

	// Where the map goes on a tap: along the closure, in the shooting area.
	if len(c.Where) == 0 || len(c.Where[0]) < 2 || len(s.Where) == 0 {
		t.Errorf("where: closure %v, shooting %v", c.Where, s.Where)
	}

	// Cached for an hour; a later day leaves out what is over by then.
	later, _, _ := f.Notices(context.Background(), line, today.AddDate(0, 0, 2))
	if calls != 1 || len(later) != 1 || later[0].Kind != "closure" {
		t.Errorf("%d calls, later: %+v", calls, later)
	}
}

// Closures are asked again after an hour: while geo.admin does not answer the
// last answer serves, with its time, and what is over stays out.
func TestNoticesLastKnown(t *testing.T) {
	ctx := context.Background()
	body, err := os.ReadFile("testdata/identify_notices.json")
	if err != nil {
		t.Fatal(err)
	}
	broken := false
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		if broken {
			w.WriteHeader(http.StatusBadGateway)
			return
		}
		_, _ = w.Write(body)
	}))
	t.Cleanup(srv.Close)
	f := &Finder{DB: testdb.New(t), URL: srv.URL}
	line := []geo.Point{{Lon: 8.0, Lat: 46.66}, {Lon: 8.02, Lat: 46.66}}
	today := time.Date(2026, 9, 28, 10, 0, 0, 0, time.UTC)
	first, at, err := f.Notices(ctx, line, today)
	if err != nil || !at.IsZero() || len(first) == 0 {
		t.Fatalf("fresh: %d %v %v", len(first), at, err)
	}
	broken = true
	if _, err := f.DB.Exec(ctx, `UPDATE area_cache SET fetched_at = now() - interval '2 hours'`); err != nil {
		t.Fatal(err)
	}
	got, at, err := f.Notices(ctx, line, today)
	if err != nil || at.IsZero() || len(got) != len(first) {
		t.Errorf("last known: %d %v %v", len(got), at, err)
	}
	if later, _, err := f.Notices(ctx, line, today.AddDate(2, 0, 0)); err != nil || len(later) != 0 {
		t.Errorf("what is over stays out: %d %v", len(later), err)
	}
	if _, _, err := f.Notices(ctx, []geo.Point{{Lon: 9, Lat: 46.7}, {Lon: 9.02, Lat: 46.7}}, today); !errors.Is(err, ErrUnavailable) {
		t.Errorf("a line never asked about: %v", err)
	}
}
