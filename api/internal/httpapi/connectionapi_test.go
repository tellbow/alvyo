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
	c.do("POST", "/api/v1/auth/signup", signupBody("pt@example.ch", "pendler"))
	if code, _ := c.do("GET", q, nil); code != http.StatusServiceUnavailable {
		t.Errorf("not configured: %d", code)
	}

	fake := &fakePlanner{}
	s2 := newTestServerWith(t, func(d *Deps) { d.Planner = fake })
	c2 := s2.client(t)
	c2.do("POST", "/api/v1/auth/signup", signupBody("pt@example.ch", "pendler"))
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
	c.do("POST", "/api/v1/auth/signup", signupBody("pt@example.ch", "pendler"))
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
