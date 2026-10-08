package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tellbow/alvyo/api/internal/routing"
)

// straightGraphHopper answers every route request with the straight line
// through its points.
func straightGraphHopper(t *testing.T) string {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req struct{ Points [][2]float64 }
		_ = json.NewDecoder(r.Body).Decode(&req)
		coords := [][]float64{}
		for _, p := range req.Points {
			coords = append(coords, []float64{p[0], p[1]})
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"paths": []any{map[string]any{
			"points":            map[string]any{"coordinates": coords},
			"snapped_waypoints": map[string]any{"coordinates": coords},
		}}})
	}))
	t.Cleanup(srv.Close)
	return srv.URL
}

type proposal struct {
	Stages []struct {
		StartPlace    *struct{ ID, Name string } `json:"start_place"`
		EndPlace      *struct{ ID, Name string } `json:"end_place"`
		Accommodation string                     `json:"accommodation"`
		Totals        struct {
			DurationS int `json:"duration_s"`
		} `json:"totals"`
		Earlier *struct{ ID, Name string } `json:"earlier"`
		Later   *struct{ ID, Name string } `json:"later"`
		Profile string                     `json:"profile"`
		Anchors []map[string]any           `json:"anchors"`
		Legs    []map[string]any           `json:"legs"`
	} `json:"stages"`
	TargetS int `json:"target_s"`
	MinS    int `json:"min_s"`
}

func TestPlanJourney(t *testing.T) {
	gh := straightGraphHopper(t)
	s := newTestServerWith(t, func(d *Deps) {
		d.Router = &routing.Router{GraphHopper: &routing.GraphHopper{URL: gh}, Elevation: flatSampler{}, Trails: &routing.TrailMatcher{DB: d.DB}}
	})
	place := func(kind, name string, lon, lat float64) string {
		var id string
		if err := s.db.QueryRow(context.Background(), `INSERT INTO places (kind, name, source, source_id, geom, website)
			VALUES ($1, $2, 'osm', $2, ST_SetSRID(ST_MakePoint($3, $4), 4326), 'https://example.ch') RETURNING id`,
			kind, name, lon, lat).Scan(&id); err != nil {
			t.Fatal(err)
		}
		return id
	}
	// A flat line of 46 km (about 11 h) with a hut 450 m off it half way, a
	// guest house before and a stop after.
	hut := place("hut", "Mittelhütte", 8.30, 46.504)
	inn := place("hotel", "Gasthaus", 8.25, 46.5)
	stop := place("pt_stop", "Dorf, Post", 8.35, 46.5)
	place("hut", "Fernhütte", 8.30, 46.53) // 3 km off: too far

	c := s.client(t)
	body := map[string]any{
		"points": []map[string]any{{"lon": 8.0, "lat": 46.5}, {"lon": 8.6, "lat": 46.5}},
		"days":   2, "kinds": []string{"hut"},
	}
	if code, _ := c.do("POST", "/api/v1/journeys/plan", body); code != http.StatusUnauthorized {
		t.Errorf("anonymous: %d", code)
	}
	s.signup(c, "planner@example.ch", "planner")
	plan := func(body map[string]any) proposal {
		t.Helper()
		code, b := c.do("POST", "/api/v1/journeys/plan", body)
		if code != http.StatusOK {
			t.Fatalf("plan: %d %s", code, b)
		}
		var p proposal
		if err := json.Unmarshal(b, &p); err != nil {
			t.Fatal(err)
		}
		return p
	}

	// Two days: the night at the hut, with the way there and back.
	p := plan(body)
	if len(p.Stages) != 2 {
		t.Fatalf("%d stages", len(p.Stages))
	}
	first, second := p.Stages[0], p.Stages[1]
	if first.EndPlace == nil || first.EndPlace.ID != hut || first.Accommodation != "Mittelhütte" ||
		second.StartPlace == nil || second.StartPlace.ID != hut || second.EndPlace != nil {
		t.Errorf("stages: %+v", p.Stages)
	}
	if first.Earlier == nil || first.Earlier.ID != inn || first.Later == nil || first.Later.ID != stop {
		t.Errorf("alternatives: earlier %+v, later %+v", first.Earlier, first.Later)
	}
	half := float64(p.TargetS)
	for i, st := range p.Stages {
		if d := float64(st.Totals.DurationS); d < half*0.9 || d > half*1.2 {
			t.Errorf("day %d: %d s, target %d s", i+1, st.Totals.DurationS, p.TargetS)
		}
	}

	// Another place instead, as chosen from the alternatives.
	body["ends"] = []string{stop}
	if p = plan(body); p.Stages[0].EndPlace.ID != stop || p.Stages[0].Accommodation != "" {
		t.Errorf("ended at the stop: %+v", p.Stages[0])
	}
	body["ends"] = []string{"01a0d22d-6521-7e24-97e6-d80c376cae63"}
	if code, _ := c.do("POST", "/api/v1/journeys/plan", body); code != http.StatusUnprocessableEntity {
		t.Errorf("unknown end: %d", code)
	}
	delete(body, "ends")
	delete(body, "days")
	if code, _ := c.do("POST", "/api/v1/journeys/plan", body); code != http.StatusUnprocessableEntity {
		t.Errorf("neither days nor hours: %d", code)
	}
	// About 11 h at 4 h a day: three days.
	body["hours_per_day"] = 4
	if p = plan(body); len(p.Stages) != 3 {
		t.Errorf("4 h a day: %d stages", len(p.Stages))
	}
	// Between 4 and 7 h a day: as few days as fit, two at the hut.
	delete(body, "hours_per_day")
	body["min_hours"], body["max_hours"] = 4, 7
	if p = plan(body); len(p.Stages) != 2 || p.Stages[0].EndPlace == nil || p.Stages[0].EndPlace.ID != hut || p.MinS != 4*3600 {
		t.Errorf("4–7 h a day: %+v", p)
	}
	for _, bad := range []map[string]any{{"min_hours": 4, "max_hours": 0}, {"min_hours": 8, "max_hours": 6}} {
		body["min_hours"], body["max_hours"] = bad["min_hours"], bad["max_hours"]
		if code, _ := c.do("POST", "/api/v1/journeys/plan", body); code != http.StatusUnprocessableEntity {
			t.Errorf("min %v, max %v: %d", bad["min_hours"], bad["max_hours"], code)
		}
	}
	delete(body, "min_hours")

	// At most so many hours a day: a day over it is refused, with the
	// fewest days that fit (Thun → Zermatt in three days at most 8 h gave a
	// day of 21 h).
	tooLong := func(body map[string]any) (int, float64) {
		t.Helper()
		code, b := c.do("POST", "/api/v1/journeys/plan", body)
		var e struct {
			Errors []struct {
				Message string  `json:"message"`
				Value   float64 `json:"value"`
			} `json:"errors"`
		}
		_ = json.Unmarshal(b, &e)
		if len(e.Errors) != 1 || e.Errors[0].Message != tooLongMessage {
			return code, -1
		}
		return code, e.Errors[0].Value
	}
	body["days"], body["max_hours"] = 1, 7
	if code, days := tooLong(body); code != http.StatusUnprocessableEntity || days != 2 {
		t.Errorf("1 day of 11 h, at most 7 h: %d, fewest %v", code, days)
	}
	body["max_hours"] = 3 // 4.5 h to the first place
	if code, days := tooLong(body); code != http.StatusUnprocessableEntity || days != 0 {
		t.Errorf("at most 3 h: %d, fewest %v", code, days)
	}
	body["days"], body["max_hours"] = 2, 7
	if p = plan(body); len(p.Stages) != 2 {
		t.Errorf("2 days at most 7 h: %d stages", len(p.Stages))
	}
	// Days the hiker chose are not refused.
	body["days"], body["ends"] = 3, []string{inn, stop}
	body["max_hours"] = 3
	if p = plan(body); len(p.Stages) != 3 {
		t.Errorf("chosen ends: %d stages", len(p.Stages))
	}
	delete(body, "ends")
	delete(body, "max_hours")
	body["days"] = 2

	// Accepted: the journey with its stages, places and accommodation.
	p = plan(map[string]any{
		"points": []map[string]any{{"lon": 8.0, "lat": 46.5}, {"lon": 8.6, "lat": 46.5}},
		"days":   2, "kinds": []string{"hut"},
	})
	var stages []map[string]any
	for _, st := range p.Stages {
		s := map[string]any{"profile": st.Profile, "anchors": st.Anchors, "legs": st.Legs, "accommodation": st.Accommodation}
		if st.StartPlace != nil {
			s["start_place_id"] = st.StartPlace.ID
		}
		if st.EndPlace != nil {
			s["end_place_id"] = st.EndPlace.ID
		}
		stages = append(stages, s)
	}
	code, b := c.do("POST", "/api/v1/journeys", map[string]any{"title": "Quer durch", "stages": stages})
	if code != http.StatusCreated {
		t.Fatalf("create: %d %s", code, b)
	}
	var j struct {
		StageList []struct {
			Route *struct {
				ID string `json:"id"`
			} `json:"route"`
			EndPlace *struct {
				ID string `json:"id"`
			} `json:"end_place"`
			Accommodation string `json:"accommodation"`
			Gap           *struct {
				Status string `json:"status"`
			} `json:"gap"`
		} `json:"stage_list"`
	}
	_ = json.Unmarshal(b, &j)
	if len(j.StageList) != 2 || j.StageList[0].Route == nil || j.StageList[0].EndPlace == nil ||
		j.StageList[0].EndPlace.ID != hut || j.StageList[0].Accommodation != "Mittelhütte" ||
		j.StageList[1].Gap == nil || j.StageList[1].Gap.Status != "ok" {
		t.Errorf("journey: %s", b)
	}
	stages[0]["end_place_id"] = "01a0d22d-6521-7e24-97e6-d80c376cae63"
	if code, b := c.do("POST", "/api/v1/journeys", map[string]any{"title": "Falsch", "stages": stages}); code != http.StatusUnprocessableEntity {
		t.Errorf("unknown place: %d %s", code, b)
	}
}

func TestSuggestJourneys(t *testing.T) {
	gh := straightGraphHopper(t)
	s := newTestServerWith(t, func(d *Deps) {
		d.Router = &routing.Router{GraphHopper: &routing.GraphHopper{URL: gh}, Elevation: flatSampler{}, Trails: &routing.TrailMatcher{DB: d.DB}}
	})
	place := func(kind, name string, lon, lat float64) string {
		var id string
		if err := s.db.QueryRow(context.Background(), `INSERT INTO places (kind, name, source, source_id, geom)
			VALUES ($1, $2, 'osm', $2, ST_SetSRID(ST_MakePoint($3, $4), 4326)) RETURNING id`,
			kind, name, lon, lat).Scan(&id); err != nil {
			t.Fatal(err)
		}
		return id
	}
	// A flat line of 46 km, a hut half way, and villages 11 km to the north
	// and to the south of it, which ways over the hills pass.
	hut := place("hut", "Mittelhütte", 8.30, 46.5)
	north := place("pt_stop", "Nordberg", 8.30, 46.604)
	south := place("pt_stop", "Südtal", 8.30, 46.396)

	c := s.client(t)
	body := map[string]any{
		"points": []map[string]any{{"lon": 8.0, "lat": 46.5}, {"lon": 8.6, "lat": 46.5}},
		"days":   2,
	}
	if code, _ := c.do("POST", "/api/v1/journeys/suggest", body); code != http.StatusUnauthorized {
		t.Errorf("anonymous: %d", code)
	}
	s.signup(c, "suggest@example.ch", "suggest")
	if code, _ := c.do("POST", "/api/v1/journeys/suggest", map[string]any{"points": body["points"]}); code != http.StatusUnprocessableEntity {
		t.Errorf("neither days nor hours: %d", code)
	}

	code, b := c.do("POST", "/api/v1/journeys/suggest", body)
	if code != http.StatusOK {
		t.Fatalf("suggest: %d %s", code, b)
	}
	var out struct {
		Suggestions []struct {
			Points   []map[string]float64 `json:"points"`
			Via      string               `json:"via"`
			Proposal proposal             `json:"proposal"`
		} `json:"suggestions"`
	}
	if err := json.Unmarshal(b, &out); err != nil {
		t.Fatal(err)
	}
	// The direct way first, sleeping at the hut; over the hills in the
	// villages.
	nights := map[string]string{"": hut, "Nordberg": north, "Südtal": south}
	if len(out.Suggestions) != 3 || out.Suggestions[0].Via != "" {
		t.Fatalf("suggestions: %s", b)
	}
	for _, sg := range out.Suggestions {
		want, ok := nights[sg.Via]
		if !ok || len(sg.Proposal.Stages) != 2 {
			t.Errorf("via %q: %d stages", sg.Via, len(sg.Proposal.Stages))
			continue
		}
		if end := sg.Proposal.Stages[0].EndPlace; end == nil || end.ID != want {
			t.Errorf("via %q: day 1 ends at %+v", sg.Via, end)
		}
		if n := len(sg.Points); sg.Via != "" && n != 3 || sg.Via == "" && n != 2 {
			t.Errorf("via %q: points %v", sg.Via, sg.Points)
		}
		delete(nights, sg.Via)
	}

	// Only ways within the most per day; none: 422 with the fewest days.
	body["days"], body["max_hours"] = 1, 7
	code, b = c.do("POST", "/api/v1/journeys/suggest", body)
	if code != http.StatusUnprocessableEntity || !strings.Contains(string(b), tooLongMessage) {
		t.Errorf("1 day at most 7 h: %d %s", code, b)
	}
	body["days"], body["max_hours"] = 2, 7
	code, b = c.do("POST", "/api/v1/journeys/suggest", body)
	out.Suggestions = nil
	if err := json.Unmarshal(b, &out); code != http.StatusOK || err != nil || len(out.Suggestions) == 0 {
		t.Fatalf("2 days at most 7 h: %d %s", code, b)
	}
	for _, sg := range out.Suggestions {
		for i, st := range sg.Proposal.Stages {
			if st.Totals.DurationS > 7*3600+15*60 {
				t.Errorf("via %q, day %d: %d s", sg.Via, i+1, st.Totals.DurationS)
			}
		}
	}
}
