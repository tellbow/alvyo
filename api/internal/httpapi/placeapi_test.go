package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
)

func TestPlacesAPI(t *testing.T) {
	s := newTestServer(t, Limits{})
	var stop string
	if err := s.db.QueryRow(context.Background(), `INSERT INTO places (kind, name, detail, source, source_id, geom)
		VALUES ('pt_stop', 'Weisstannen, Oberdorf', 'Bus', 'didok', '8509965', ST_SetSRID(ST_MakePoint(8.0021, 46.5), 4326))
		RETURNING id`).Scan(&stop); err != nil {
		t.Fatal(err)
	}
	c := s.client(t)
	c.do("POST", "/api/v1/auth/signup", signupBody("stops@example.ch", "stops"))

	code, body := c.do("GET", "/api/v1/places/nearby?lon=8.002&lat=46.5&kind=pt_stop,hut", nil)
	var res struct {
		Places []struct {
			ID        string  `json:"id"`
			Name      string  `json:"name"`
			DistanceM float64 `json:"distance_m"`
		} `json:"places"`
	}
	if err := json.Unmarshal(body, &res); code != http.StatusOK || err != nil || len(res.Places) != 1 || res.Places[0].ID != stop {
		t.Fatalf("nearby: %d %s", code, body)
	}
	for _, q := range []string{"lon=8.002&lat=46.5&kind=peak", "lon=2.3&lat=48.8", "lat=46.5"} {
		if code, body := c.do("GET", "/api/v1/places/nearby?"+q, nil); code != http.StatusUnprocessableEntity {
			t.Errorf("%s: %d %s", q, code, body)
		}
	}

	// The stop is suggested for the end of a stage ending 8 m from it, and can
	// be chosen explicitly (the route is short: it is suggested as start too).
	_, body = c.do("POST", "/api/v1/journeys", map[string]any{"title": "Stops", "visibility": "private"})
	j := decodeJourney(t, body)
	_, body = c.do("POST", "/api/v1/journeys/"+j.ID+"/stages", map[string]any{})
	j = decodeJourney(t, body)
	sid := j.StageList[0].ID
	if code, body := c.do("POST", "/api/v1/journeys/"+j.ID+"/stages/"+sid+"/route", stageRouteBody(8.0)); code != http.StatusOK {
		t.Fatalf("stage route: %d %s", code, body)
	}
	type placeRef struct {
		ID        string `json:"id"`
		Suggested bool   `json:"suggested"`
	}
	stagePlaces := func(body []byte) (start, end *placeRef) {
		var r struct {
			StageList []struct {
				StartPlace *placeRef `json:"start_place"`
				EndPlace   *placeRef `json:"end_place"`
			} `json:"stage_list"`
		}
		if err := json.Unmarshal(body, &r); err != nil {
			t.Fatal(err)
		}
		return r.StageList[0].StartPlace, r.StageList[0].EndPlace
	}
	_, body = c.do("GET", "/api/v1/journeys/"+j.ID, nil)
	if _, end := stagePlaces(body); end == nil || end.ID != stop || !end.Suggested {
		t.Errorf("suggested end %+v", end)
	}
	jp := "/api/v1/journeys/" + j.ID
	code, body = c.do("PATCH", jp+"/stages/"+sid, map[string]any{"start_place_id": stop}, stageMatch(t, c, jp, sid)...)
	if start, _ := stagePlaces(body); code != http.StatusOK || start == nil || start.ID != stop || start.Suggested {
		t.Errorf("chosen start: %d %s", code, body)
	}
	if code, body := c.do("PATCH", jp+"/stages/"+sid,
		map[string]any{"end_place_id": "00000000-0000-0000-0000-000000000000"}, stageMatch(t, c, jp, sid)...); code != http.StatusUnprocessableEntity {
		t.Errorf("unknown place: %d %s", code, body)
	}
}

func TestSearchPlacesAPI(t *testing.T) {
	s := newTestServer(t, Limits{})
	if _, err := s.db.Exec(context.Background(), `INSERT INTO places (kind, name, detail, source, source_id, geom)
		VALUES ('pt_stop', 'Weisstannen, Oberdorf', 'Bus', 'didok', '8509965', ST_SetSRID(ST_MakePoint(9.35, 47.03), 4326))`); err != nil {
		t.Fatal(err)
	}
	c := s.client(t)
	if code, _ := c.do("GET", "/api/v1/places/search?q=weiss", nil); code != http.StatusUnauthorized {
		t.Errorf("anonymous: %d", code)
	}
	c.do("POST", "/api/v1/auth/signup", signupBody("search@example.ch", "search"))

	code, body := c.do("GET", "/api/v1/places/search?q=weisstannen&lon=9.3&lat=47", nil)
	var res struct {
		Places []struct {
			Name, Detail, Kind string
			At                 [2]float64
		} `json:"places"`
	}
	if err := json.Unmarshal(body, &res); code != http.StatusOK || err != nil || len(res.Places) != 1 ||
		res.Places[0].Kind != "pt_stop" || res.Places[0].Detail != "Bus" || res.Places[0].At != [2]float64{9.35, 47.03} {
		t.Fatalf("search: %d %s", code, body)
	}
	if code, _ := c.do("GET", "/api/v1/places/search?q=w", nil); code != http.StatusUnprocessableEntity {
		t.Errorf("one letter: %d", code)
	}

	// A point found by search keeps its name in the saved route.
	route := newRouteBody("Named", "private")
	route["anchors"].([]map[string]any)[0]["name"] = "Weisstannen, Oberdorf"
	_, body = c.do("POST", "/api/v1/routes", route)
	var saved struct {
		ID      string `json:"id"`
		Anchors []struct {
			Name string `json:"name"`
		} `json:"anchors"`
	}
	_ = json.Unmarshal(body, &saved)
	_, body = c.do("GET", "/api/v1/routes/"+saved.ID, nil)
	_ = json.Unmarshal(body, &saved)
	if len(saved.Anchors) != 3 || saved.Anchors[0].Name != "Weisstannen, Oberdorf" || saved.Anchors[1].Name != "" {
		t.Errorf("anchors %s", body)
	}
}
