package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/tellbow/odysgeh/api/internal/auth"
	"github.com/tellbow/odysgeh/api/internal/mailer"
	"github.com/tellbow/odysgeh/api/internal/routing"
	"github.com/tellbow/odysgeh/api/internal/testdb"
	"github.com/tellbow/odysgeh/swiss/geo"
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
}
