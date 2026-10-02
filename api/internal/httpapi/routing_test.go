package httpapi

import (
	"context"
	"encoding/json"
	"math"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/tellbow/alvyo/api/internal/auth"
	"github.com/tellbow/alvyo/api/internal/mailer"
	"github.com/tellbow/alvyo/api/internal/routing"
	"github.com/tellbow/alvyo/api/internal/testdb"
	"github.com/tellbow/alvyo/swiss/geo"
)

type flatSampler struct{}

func (flatSampler) Sample(_ context.Context, pts []geo.Point) ([]float64, error) {
	return make([]float64, len(pts)), nil
}

// newRoutingServer serves the recorded First → Bachalpsee GraphHopper
// response for every route request, or a PointNotFound error if broken.
func newRoutingServer(t *testing.T) *testServer {
	t.Helper()
	fixture, err := os.ReadFile("../routing/testdata/gh_first_bachalpsee.json")
	if err != nil {
		t.Fatal(err)
	}
	gh := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req struct{ Points [][2]float64 }
		_ = json.NewDecoder(r.Body).Decode(&req)
		if req.Points[0][0] < 7 { // "far away" test point
			w.WriteHeader(http.StatusBadRequest)
			_, _ = w.Write([]byte(`{"message":"Cannot find point 0","hints":[{"details":"com.graphhopper.util.exceptions.PointNotFoundException"}]}`))
			return
		}
		_, _ = w.Write(fixture)
	}))
	t.Cleanup(gh.Close)

	pool := testdb.New(t)
	rec := &mailer.Recorder{}
	h, _ := New(Deps{
		DB:   pool,
		Auth: &auth.Service{DB: pool, Mail: rec, PublicURL: origin},
		Router: &routing.Router{
			GraphHopper: &routing.GraphHopper{URL: gh.URL},
			Elevation:   flatSampler{},
			Trails:      &routing.TrailMatcher{DB: pool},
		},
		PublicURL: origin,
	})
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	return &testServer{Server: srv, mail: rec}
}

func legBody(fromLon float64) map[string]any {
	return map[string]any{
		"from": map[string]any{"lon": fromLon, "lat": 46.6597},
		"to":   map[string]any{"lon": 8.0247, "lat": 46.6703},
	}
}

func TestRouteLeg(t *testing.T) {
	s := newRoutingServer(t)
	c := s.client(t)

	if code, _ := c.do("POST", "/api/v1/routing/leg", legBody(8.0535)); code != http.StatusUnauthorized {
		t.Errorf("anonymous leg: %d, want 401", code)
	}
	c.do("POST", "/api/v1/auth/signup", signupBody("fiona@example.ch", "fiona"))

	code, body := c.do("POST", "/api/v1/routing/leg", legBody(8.0535))
	if code != http.StatusOK {
		t.Fatalf("leg: %d %s", code, body)
	}
	var leg routing.Leg
	if err := json.Unmarshal(body, &leg); err != nil {
		t.Fatal(err)
	}
	if leg.DistanceM < 2800 || len(leg.Coordinates) < 100 || leg.SAC.Grade != 2 || leg.Warnings == nil {
		t.Errorf("leg: %.0f m, %d vertices, T%d, warnings %v", leg.DistanceM, len(leg.Coordinates), leg.SAC.Grade, leg.Warnings)
	}

	// Outside Switzerland → validation error; unroutable point → 422 message.
	if code, _ := c.do("POST", "/api/v1/routing/leg", legBody(2.35)); code != http.StatusUnprocessableEntity {
		t.Errorf("out of bounds: %d", code)
	}
	code, body = c.do("POST", "/api/v1/routing/leg", legBody(6.5))
	if code != http.StatusUnprocessableEntity || !json.Valid(body) {
		t.Errorf("no path: %d %s", code, body)
	}

	if code, body := c.do("GET", "/api/v1/routing/profiles", nil); code != http.StatusOK {
		t.Errorf("profiles: %d %s", code, body)
	}

	// The ways a leg can be dragged onto, as lines; a point without a path: 422.
	code, body = c.do("POST", "/api/v1/routing/alternatives", legBody(8.0535))
	var alts struct{ Ways [][][2]float64 }
	if err := json.Unmarshal(body, &alts); code != http.StatusOK || err != nil || len(alts.Ways) == 0 || len(alts.Ways[0]) < 100 {
		t.Errorf("alternatives: %d %.200s", code, body)
	}
	if code, _ := c.do("POST", "/api/v1/routing/alternatives", legBody(6.5)); code != http.StatusUnprocessableEntity {
		t.Errorf("alternatives without a path: %d", code)
	}
}

func TestRouteTurns(t *testing.T) {
	// GraphHopper matches the line of newRouteBody (8.0 → 8.004 at 46.5° N)
	// onto itself, turning right at 8.002.
	var failing atomic.Bool
	gh := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/match" || failing.Load() {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		_, _ = w.Write([]byte(`{"paths":[{"points":{"coordinates":[[8.0,46.5],[8.002,46.5],[8.004,46.5]]},
			"instructions":[{"sign":0,"interval":[0,1]},{"sign":2,"interval":[1,2]},{"sign":4,"interval":[2,2]}]}]}`))
	}))
	t.Cleanup(gh.Close)
	s := newTestServerWith(t, func(d *Deps) {
		d.Router = &routing.Router{GraphHopper: &routing.GraphHopper{URL: gh.URL}}
	})
	owner, other, anon := s.client(t), s.client(t), s.client(t)
	owner.do("POST", "/api/v1/auth/signup", signupBody("owner@example.ch", "owner"))
	other.do("POST", "/api/v1/auth/signup", signupBody("other@example.ch", "other"))
	_, body := owner.do("POST", "/api/v1/routes", newRouteBody("Gratweg", "private"))
	var r savedRoute
	_ = json.Unmarshal(body, &r)
	path := "/api/v1/routes/" + r.ID + "/turns"

	code, body := owner.do("GET", path, nil)
	var out struct{ Turns []routing.Turn }
	if err := json.Unmarshal(body, &out); code != http.StatusOK || err != nil {
		t.Fatalf("turns: %d %s", code, body)
	}
	if len(out.Turns) != 1 || out.Turns[0].Kind != "right" || math.Abs(out.Turns[0].AlongM-153) > 2 {
		t.Errorf("turns: %s", body)
	}
	if code, _ := anon.do("GET", path, nil); code != http.StatusUnauthorized {
		t.Errorf("anonymous: %d", code)
	}
	if code, _ := other.do("GET", path, nil); code != http.StatusNotFound {
		t.Errorf("someone else's private route: %d", code)
	}
	failing.Store(true)
	if code, _ := owner.do("GET", path, nil); code != http.StatusServiceUnavailable {
		t.Errorf("GraphHopper down: %d", code)
	}
}

func TestInternalErrorsHidden(t *testing.T) {
	// GraphHopper fails with a message of its own: the client sees only that
	// something went wrong.
	gh := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte(`{"message":"java.lang.OutOfMemoryError at /opt/graphhopper/secret"}`))
	}))
	t.Cleanup(gh.Close)
	s := newTestServerWith(t, func(d *Deps) {
		d.Router = &routing.Router{GraphHopper: &routing.GraphHopper{URL: gh.URL}, Elevation: flatSampler{}}
	})
	c := s.client(t)
	c.do("POST", "/api/v1/auth/signup", signupBody("fiona@example.ch", "fiona"))
	code, body := c.do("POST", "/api/v1/routing/leg", legBody(8.0535))
	if code != http.StatusInternalServerError || strings.Contains(string(body), "secret") || strings.Contains(string(body), "graphhopper") {
		t.Errorf("leg: %d %s", code, body)
	}
}
