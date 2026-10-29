package httpapi

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/tellbow/alvyo/swiss/geo"
)

// steepTerrain is 32° everywhere.
type steepTerrain struct{}

func (steepTerrain) Slope(geo.Point) (float64, error) { return 32, nil }

func TestRouteSteepness(t *testing.T) {
	s := newTestServerWith(t, func(d *Deps) { d.Terrain = steepTerrain{} })
	owner := s.client(t)
	s.signup(owner, "steep@example.ch", "steep")
	code, body := owner.do("POST", "/api/v1/routes", newRouteBody("Grat", "private"))
	var r savedRoute
	if err := json.Unmarshal(body, &r); err != nil || code != http.StatusCreated {
		t.Fatalf("route: %d %s", code, body)
	}

	code, body = owner.do("GET", "/api/v1/routes/"+r.ID+"/steepness", nil)
	var got struct {
		Known     bool    `json:"known"`
		SteepM    float64 `json:"steep_m"`
		Stretches []struct {
			Class int `json:"class"`
		} `json:"stretches"`
	}
	if err := json.Unmarshal(body, &got); err != nil || code != http.StatusOK {
		t.Fatalf("steepness: %d %s", code, body)
	}
	if !got.Known || got.SteepM < 250 || len(got.Stretches) != 1 || got.Stretches[0].Class != 2 {
		t.Errorf("%s", body)
	}
	// Only who may open the route.
	if code, _ := s.client(t).do("GET", "/api/v1/routes/"+r.ID+"/steepness", nil); code != http.StatusNotFound {
		t.Errorf("anonymous: %d", code)
	}
}
