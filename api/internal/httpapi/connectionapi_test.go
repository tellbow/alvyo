package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/tellbow/alvyo/api/internal/routing"
	"github.com/tellbow/alvyo/swiss/ojp"
)

type fakePlanner struct {
	calls atomic.Int32
	last  ojp.Query
	fail  bool
}

func (f *fakePlanner) Trips(_ context.Context, q ojp.Query) ([]ojp.Trip, error) {
	f.calls.Add(1)
	f.last = q
	if f.fail {
		return nil, errors.New("down")
	}
	dep := q.At.Add(3 * time.Minute)
	return []ojp.Trip{{Start: dep, End: dep.Add(39 * time.Minute), Legs: []ojp.Leg{
		{Kind: "ride", Mode: "bus", Line: "B 432", From: "Sargans, Bahnhof", To: "Weisstannen, Oberdorf",
			Departure: dep, Arrival: dep.Add(36 * time.Minute)},
	}}}, nil
}

func TestConnections(t *testing.T) {
	s := newTestServer(t, Limits{})
	c := s.client(t)
	const q = "/api/v1/connections?from=8509411&to=8509965&date=2026-07-04&time=08:00"

	if code, _ := c.do("GET", q, nil); code != http.StatusUnauthorized {
		t.Errorf("anonymous: %d", code)
	}
	s.signup(c, "pt@example.ch", "pendler")
	if code, _ := c.do("GET", q, nil); code != http.StatusServiceUnavailable {
		t.Errorf("not configured: %d", code)
	}

	fake := &fakePlanner{}
	s2 := newTestServerWith(t, func(d *Deps) { d.Planner = fake })
	c2 := s2.client(t)
	s2.signup(c2, "pt@example.ch", "pendler")
	code, body := c2.do("GET", q, nil)
	var out struct {
		Trips []struct {
			Start string `json:"start"`
			Legs  []struct {
				Line      string `json:"line"`
				Departure string `json:"departure"`
			} `json:"legs"`
		} `json:"trips"`
	}
	if err := json.Unmarshal(body, &out); code != http.StatusOK || err != nil || len(out.Trips) != 1 || out.Trips[0].Legs[0].Line != "B 432" {
		t.Fatalf("connections: %d %s", code, body)
	}
	// 08:00 Swiss summer time is 06:00 UTC.
	if want := time.Date(2026, 7, 4, 6, 0, 0, 0, time.UTC); !fake.last.At.Equal(want) || fake.last.Arrive {
		t.Errorf("query %+v", fake.last)
	}
	c2.do("GET", q, nil) // cached
	if n := fake.calls.Load(); n != 1 {
		t.Errorf("planner called %d times", n)
	}
	c2.do("GET", q+"&arrive=true", nil)
	if n := fake.calls.Load(); n != 2 || !fake.last.Arrive {
		t.Errorf("arrival search: %d calls, %+v", n, fake.last)
	}

	for _, bad := range []string{
		"/api/v1/connections?from=Sargans&to=8509965&date=2026-07-04",
		"/api/v1/connections?from=8509411&to=8509965&date=4.7.2026",
		"/api/v1/connections?from=8509411&to=8509965&date=2026-07-04&time=8am",
	} {
		if code, _ := c2.do("GET", bad, nil); code != http.StatusUnprocessableEntity {
			t.Errorf("%s: %d", bad, code)
		}
	}
	fake.fail = true
	if code, _ := c2.do("GET", "/api/v1/connections?from=8509411&to=8509965&date=2026-07-04&time=09:00", nil); code != http.StatusBadGateway {
		t.Errorf("planner down: %d", code)
	}
}

// From an address (a home) to a stop, with the ways to draw.
func TestConnectionsFromAPosition(t *testing.T) {
	fake := &fakePlanner{}
	s := newTestServerWith(t, func(d *Deps) { d.Planner = fake })
	c := s.client(t)
	s.signup(c, "pt@example.ch", "pendler")
	q := "/api/v1/connections?from=7.6197,46.764&from_name=Zuhause&to=8507483&date=2026-07-04&time=06:00&lines=true"
	if code, body := c.do("GET", q, nil); code != http.StatusOK {
		t.Fatalf("%d %s", code, body)
	}
	if f := fake.last.From; f.Ref != "" || f.Lon != 7.6197 || f.Lat != 46.764 || f.Name != "Zuhause" || fake.last.To.Ref != "8507483" || !fake.last.Lines {
		t.Errorf("query %+v", fake.last)
	}
	// Without the ways it is another answer, not the cached one.
	c.do("GET", strings.Replace(q, "&lines=true", "", 1), nil)
	if fake.calls.Load() != 2 || fake.last.Lines {
		t.Errorf("%d calls, %+v", fake.calls.Load(), fake.last)
	}
	for _, bad := range []string{
		"/api/v1/connections?from=200.5,46.7&to=8507483&date=2026-07-04",
		"/api/v1/connections?from=7.6,46.7,1&to=8507483&date=2026-07-04",
	} {
		if code, _ := c.do("GET", bad, nil); code != http.StatusUnprocessableEntity {
			t.Errorf("%s: %d", bad, code)
		}
	}
}

// Answers only for stop 8500002: none for positions (out of the planner's
// reach) and none for 8500001 (a lift closed for the season).
type valleyPlanner struct{ asked []ojp.Query }

func (f *valleyPlanner) Trips(_ context.Context, q ojp.Query) ([]ojp.Trip, error) {
	f.asked = append(f.asked, q)
	if q.To.Ref != "8500002" && q.From.Ref != "8500002" {
		return []ojp.Trip{}, nil // as ojp.Parse answers TRIP_NOTRIPFOUND
	}
	return []ojp.Trip{{Start: q.At.Add(-time.Hour), End: q.At, Legs: []ojp.Leg{
		{Kind: "ride", Mode: "bus", Line: "B 230", From: "Oey-Diemtigen", To: "Riedli", Departure: q.At.Add(-time.Hour), Arrival: q.At},
	}}}, nil
}

// A route's start high on a mountain (feedback issue 89): the trips go to
// the stop with the shortest hike that has some, and the hike is added.
func TestConnectionsHikeFromAStop(t *testing.T) {
	gh := straightGraphHopper(t)
	fake := &valleyPlanner{}
	s := newTestServerWith(t, func(d *Deps) {
		d.Planner = fake
		d.Router = &routing.Router{GraphHopper: &routing.GraphHopper{URL: gh}, Elevation: flatSampler{}, Trails: &routing.TrailMatcher{DB: d.DB}}
	})
	stop := func(ref, name string, lon, lat float64) {
		if _, err := s.db.Exec(context.Background(), `INSERT INTO places (kind, name, source, source_id, geom)
			VALUES ('pt_stop', $2, 'didok', $1, ST_SetSRID(ST_MakePoint($3, $4), 4326))`, ref, name, lon, lat); err != nil {
			t.Fatal(err)
		}
	}
	// The start at 7.53/46.58; on flat ground 1 km is about 14 min.
	stop("8500001", "Wiriehorn, Bergstation", 7.53, 46.589)       // 1 km, no service
	stop("8500002", "Riedli, Talstation Wiriehorn", 7.53, 46.607) // 3 km
	stop("8500003", "Fernwald", 7.53, 46.67)                      // 10 km: too far
	c := s.client(t)
	s.signup(c, "pt@example.ch", "berg")

	var out struct {
		Trips []struct {
			Start, End string
			Legs       []struct {
				Kind        string
				From, To    string
				Hike        bool
				DurationMin int `json:"duration_min"`
				Track       [][2]float64
			}
		}
	}
	get := func(q string) {
		t.Helper()
		code, body := c.do("GET", q, nil)
		out.Trips = nil
		if err := json.Unmarshal(body, &out); code != http.StatusOK || err != nil {
			t.Fatalf("%s: %d %s", q, code, body)
		}
	}

	// There, arriving by 08:00 at the start: at the stop by 08:00 less the hike.
	get("/api/v1/connections?from=7.4146,46.9244&from_name=Köniz&to=7.53,46.58&to_name=Wiriehorn&date=2026-11-11&time=08:00&arrive=true&lines=true&trailhead=to")
	if len(out.Trips) != 1 || len(out.Trips[0].Legs) != 2 {
		t.Fatalf("trips %+v", out.Trips)
	}
	hike := out.Trips[0].Legs[1]
	if !hike.Hike || hike.Kind != "walk" || hike.From != "Riedli, Talstation Wiriehorn" || hike.To != "Wiriehorn" ||
		hike.DurationMin < 35 || hike.DurationMin > 50 || len(hike.Track) < 2 {
		t.Errorf("hike %+v", hike)
	}
	last := fake.asked[len(fake.asked)-1]
	walk := time.Duration(hike.DurationMin) * time.Minute
	if want := time.Date(2026, 11, 11, 7, 0, 0, 0, time.UTC).Add(-walk); last.To.Ref != "8500002" || !last.At.Equal(want) {
		t.Errorf("asked %+v, want at %v", last, want)
	}
	if end, _ := time.Parse(time.RFC3339, out.Trips[0].End); !end.Equal(time.Date(2026, 11, 11, 7, 0, 0, 0, time.UTC)) {
		t.Errorf("end %s", out.Trips[0].End)
	}
	var refs []string
	for _, q := range fake.asked {
		refs = append(refs, q.To.Ref)
	}
	// The position, the lift (nearest, no service), then the valley; not the far one.
	if strings.Join(refs, " ") != " 8500001 8500002" {
		t.Errorf("asked for %q", refs)
	}

	// Back, leaving the end at 15:00: the bus after the hike, the hike first.
	fake.asked = nil
	get("/api/v1/connections?from=7.53,46.58&from_name=Wiriehorn&to=7.4146,46.9244&to_name=Köniz&date=2026-11-11&time=15:00&trailhead=from")
	if len(out.Trips) != 1 || !out.Trips[0].Legs[0].Hike || out.Trips[0].Legs[0].To != "Riedli, Talstation Wiriehorn" {
		t.Fatalf("trips %+v", out.Trips)
	}
	last = fake.asked[len(fake.asked)-1]
	walk = time.Duration(out.Trips[0].Legs[0].DurationMin) * time.Minute
	if want := time.Date(2026, 11, 11, 14, 0, 0, 0, time.UTC).Add(walk); last.From.Ref != "8500002" || !last.At.Equal(want) {
		t.Errorf("asked %+v, want at %v", last, want)
	}

	// Without a trailhead, nothing is added; with one but no stop near, an
	// empty list as before (not null).
	get("/api/v1/connections?from=7.4146,46.9244&to=7.53,46.58&date=2026-11-11&time=09:00")
	if len(out.Trips) != 0 {
		t.Errorf("trips %+v", out.Trips)
	}
	if code, body := c.do("GET", "/api/v1/connections?from=7.4146,46.9244&to=8.9,46.3&date=2026-11-11&trailhead=to", nil); code != http.StatusOK || !strings.Contains(string(body), `"trips":[]`) {
		t.Errorf("no stop near: %d %s", code, body)
	}
}
