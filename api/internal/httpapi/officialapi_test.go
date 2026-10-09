package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
)

func TestOfficialRoutesAndCopies(t *testing.T) {
	s := newTestServer(t, Limits{})
	ctx := context.Background()
	exec := func(sql string, args ...any) {
		t.Helper()
		if _, err := s.db.Exec(ctx, sql, args...); err != nil {
			t.Fatal(err)
		}
	}
	hiker, other, anon := s.client(t), s.client(t), s.client(t)
	s.signup(hiker, "berg@example.ch", "berg")
	s.signup(other, "tal@example.ch", "tal")
	exec(`UPDATE users SET email_verified_at = now()`)
	create := func(c *client, path string, body map[string]any) []byte {
		t.Helper()
		code, resp := c.do("POST", path, body)
		if code != http.StatusCreated && code != http.StatusOK {
			t.Fatalf("POST %s: %d %s", path, code, resp)
		}
		return resp
	}
	var versoix, mine, hike savedRoute
	_ = json.Unmarshal(create(hiker, "/api/v1/routes", lineRoute("Au fil de la Versoix", "public", 8.000, 46.6, "T1")), &versoix)
	_ = json.Unmarshal(create(hiker, "/api/v1/routes", lineRoute("Mein Weg", "public", 8.004, 46.6, "T2")), &mine)
	_ = json.Unmarshal(create(other, "/api/v1/routes", lineRoute("Gewandert", "public", 8.008, 46.6, "T2")), &hike)
	j := decodeJourney(t, create(hiker, "/api/v1/journeys", map[string]any{"title": "Via Alpina", "visibility": "public"}))
	jbase := "/api/v1/journeys/" + j.ID
	j = decodeJourney(t, create(hiker, jbase+"/stages", map[string]any{"title": "Vaduz – Sargans"}))
	create(hiker, jbase+"/stages/"+j.StageList[0].ID+"/route", stageRouteBody(8.0))
	j = decodeJourney(t, func() []byte { _, b := anon.do("GET", jbase, nil); return b }())

	// As the sync leaves them: owned by «wanderland», listed in official.
	exec(`UPDATE routes SET owner_id = (SELECT id FROM users WHERE username = 'wanderland')
		WHERE id = $1 OR journey_id = $2`, versoix.ID, j.ID)
	exec(`UPDATE journeys SET owner_id = (SELECT id FROM users WHERE username = 'wanderland') WHERE id = $1`, j.ID)
	exec(`INSERT INTO official (nr, kind, route_id, hash) VALUES ('104', 'local', $1, '')`, versoix.ID)
	exec(`INSERT INTO official (nr, kind, journey_id, hash) VALUES ('1', 'national', $1, '')`, j.ID)
	// tal recorded «Gewandert» with the app.
	exec(`UPDATE routes SET source = 'recorded', source_ref = 'rec-1', hiked_at = now(), hiked_s = 3600 WHERE id = $1`, hike.ID)

	type info struct {
		Official *struct {
			Number string `json:"number"`
			Kind   string `json:"kind"`
		} `json:"official"`
	}
	get := func(path string) info {
		t.Helper()
		code, body := anon.do("GET", path, nil)
		if code != http.StatusOK {
			t.Fatalf("GET %s: %d %s", path, code, body)
		}
		var in info
		_ = json.Unmarshal(body, &in)
		return in
	}
	if o := get("/api/v1/routes/" + versoix.ID).Official; o == nil || o.Number != "104" || o.Kind != "local" {
		t.Errorf("official route: %+v", o)
	}
	if o := get("/api/v1/routes/" + j.StageList[0].Route.ID).Official; o == nil || o.Number != "1" {
		t.Errorf("stage of an official journey: %+v", o)
	}
	if o := get(jbase).Official; o == nil || o.Number != "1" || o.Kind != "national" {
		t.Errorf("official journey: %+v", o)
	}
	if o := get("/api/v1/routes/" + mine.ID).Official; o != nil {
		t.Errorf("someone's route: %+v", o)
	}

	discover := func(filter string) string {
		t.Helper()
		code, body := anon.do("GET", "/api/v1/discover?bbox=7.99,46.49,8.02,46.61"+filter, nil)
		if code != http.StatusOK {
			t.Fatalf("discover: %d %s", code, body)
		}
		var r discoverResp
		_ = json.Unmarshal(body, &r)
		return r.titles()
	}
	if got := discover("&official=only"); got != "Via Alpina,Au fil de la Versoix" && got != "Au fil de la Versoix,Via Alpina" {
		t.Errorf("only official: %s", got)
	}
	_, body := anon.do("GET", "/api/v1/discover?bbox=7.99,46.49,8.02,46.61&official=only&kind=route", nil)
	var found struct {
		Items []info `json:"items"`
	}
	_ = json.Unmarshal(body, &found)
	if len(found.Items) != 1 || found.Items[0].Official == nil || found.Items[0].Official.Number != "104" {
		t.Errorf("discover: %s", body)
	}
	// («Gewandert», a recorded hike of 150 m, is all within its hidden ends.)
	if got := discover("&official=none"); got != "Mein Weg" {
		t.Errorf("only people's: %s", got)
	}

	// Copies: one's own, private, the same line; not others' recorded hikes.
	if code, _ := anon.do("POST", "/api/v1/routes/"+versoix.ID+"/copy", nil); code != http.StatusUnauthorized {
		t.Errorf("copy without login: %d", code)
	}
	var cp struct {
		savedRoute
		Visibility    string `json:"visibility"`
		OwnerUsername string `json:"owner_username"`
	}
	_ = json.Unmarshal(create(other, "/api/v1/routes/"+versoix.ID+"/copy", nil), &cp)
	if cp.ID == versoix.ID || cp.Title != "Au fil de la Versoix" || cp.Visibility != "private" || cp.OwnerUsername != "tal" ||
		cp.Totals.DistanceM != versoix.Totals.DistanceM {
		t.Errorf("copy: %+v, original %+v", cp, versoix)
	}
	if o := get("/api/v1/routes/" + versoix.ID).Official; o == nil {
		t.Error("the original lost its mark")
	}
	if code, _ := hiker.do("POST", "/api/v1/routes/"+hike.ID+"/copy", nil); code != http.StatusForbidden {
		t.Errorf("copy of someone's recorded hike: %d", code)
	}
	create(other, "/api/v1/routes/"+hike.ID+"/copy", nil) // one's own
	if code, _ := hiker.do("POST", "/api/v1/routes/"+mine.ID+"/copy?t=nope", nil); code != http.StatusCreated {
		t.Errorf("copy of a public route: %d", code)
	}

	jc := decodeJourney(t, create(other, jbase+"/copy", nil))
	if jc.ID == j.ID || len(jc.StageList) != 1 || jc.StageList[0].Title != "Vaduz – Sargans" || jc.StageList[0].Route == nil {
		t.Fatalf("journey copy: %+v", jc)
	}
	var jv struct {
		Visibility    string `json:"visibility"`
		OwnerUsername string `json:"owner_username"`
	}
	_, body = other.do("GET", "/api/v1/journeys/"+jc.ID, nil)
	_ = json.Unmarshal(body, &jv)
	if jv.Visibility != "private" || jv.OwnerUsername != "tal" {
		t.Errorf("journey copy: %+v", jv)
	}
}
