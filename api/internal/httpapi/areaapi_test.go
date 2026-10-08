package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"sync/atomic"
	"testing"

	"github.com/tellbow/alvyo/api/internal/areas"
)

func TestProtectedAreas(t *testing.T) {
	fixture, err := os.ReadFile("../areas/testdata/identify_grindelwald.json")
	if err != nil {
		t.Fatal(err)
	}
	var broken atomic.Bool
	geoadmin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		if broken.Load() {
			w.WriteHeader(http.StatusBadGateway)
			return
		}
		_, _ = w.Write(fixture)
	}))
	t.Cleanup(geoadmin.Close)
	s := newTestServerWith(t, func(d *Deps) { d.Areas = &areas.Finder{DB: d.DB, URL: geoadmin.URL} })
	owner, other := s.client(t), s.client(t)
	s.signup(owner, "owner@example.ch", "owner")
	s.signup(other, "other@example.ch", "other")
	type resp struct {
		Areas []areas.Area `json:"areas"`
	}
	get := func(c *client, method, path string, body any) (int, resp) {
		t.Helper()
		code, raw := c.do(method, path, body)
		var r resp
		_ = json.Unmarshal(raw, &r)
		return code, r
	}

	line := [][2]float64{{8.0, 46.66}, {8.04, 46.665}}
	if code, _ := get(s.client(t), "POST", "/api/v1/routing/areas", map[string]any{"line": line}); code != http.StatusUnauthorized {
		t.Errorf("anonymous: %d", code)
	}
	code, r := get(owner, "POST", "/api/v1/routing/areas", map[string]any{"line": line})
	if code != http.StatusOK || len(r.Areas) != 3 || r.Areas[0].Kind != "wildlife_rest" || r.Areas[0].Period == nil {
		t.Fatalf("line: %d %+v", code, r)
	}

	// A saved route: only for those who may see it.
	_, raw := owner.do("POST", "/api/v1/routes", newRouteBody("Gratweg", "private"))
	var route savedRoute
	_ = json.Unmarshal(raw, &route)
	if code, r := get(owner, "GET", "/api/v1/routes/"+route.ID+"/areas", nil); code != http.StatusOK || len(r.Areas) != 3 {
		t.Errorf("route: %d %+v", code, r)
	}
	if code, _ := get(other, "GET", "/api/v1/routes/"+route.ID+"/areas", nil); code != http.StatusNotFound {
		t.Errorf("other's route: %d", code)
	}

	// A journey: each area once, with the stages crossing it.
	_, raw = owner.do("POST", "/api/v1/journeys", map[string]any{"title": "Zwei Tage"})
	jr := "/api/v1/journeys/" + decodeJourney(t, raw).ID
	for i := range 3 {
		_, raw = owner.do("POST", jr+"/stages", map[string]any{})
		if i < 2 { // the third stage has no route
			st := decodeJourney(t, raw).StageList[i].ID
			owner.do("POST", jr+"/stages/"+st+"/route", stageRouteBody(8.0+float64(i)*0.002))
		}
	}
	code, r = get(owner, "GET", jr+"/areas", nil)
	if code != http.StatusOK || len(r.Areas) != 3 || len(r.Areas[0].Stages) != 2 || r.Areas[0].Stages[1] != 2 {
		t.Errorf("journey: %d %+v", code, r)
	}

	// geo.admin down: 503, retried later (nothing cached from it).
	broken.Store(true)
	if code, _ := get(owner, "POST", "/api/v1/routing/areas", map[string]any{"line": [][2]float64{{8.1, 46.6}, {8.2, 46.6}}}); code != http.StatusServiceUnavailable {
		t.Errorf("geo.admin down: %d", code)
	}
}
