package httpapi

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"testing"
)

type journeyResp struct {
	ID         string `json:"id"`
	Version    int    `json:"version"`
	CanEdit    bool   `json:"can_edit"`
	ShareToken string `json:"share_token"`
	StageList  []struct {
		ID          string  `json:"id"`
		Title       string  `json:"title"`
		PlannedDate *string `json:"planned_date"`
		Status      string  `json:"status"`
		Route       *struct {
			ID string `json:"id"`
		} `json:"route"`
		Gap *struct {
			Status string `json:"status"`
		} `json:"gap"`
	} `json:"stage_list"`
	Progress struct {
		StagesDone int `json:"stages_done"`
	} `json:"progress"`
	Profile struct {
		Breaks []int `json:"breaks"`
	} `json:"profile"`
}

func decodeJourney(t *testing.T, body []byte) journeyResp {
	t.Helper()
	var j journeyResp
	if err := json.Unmarshal(body, &j); err != nil {
		t.Fatalf("%v: %s", err, body)
	}
	return j
}

func stageRouteBody(lon0 float64) map[string]any {
	return map[string]any{
		"profile": "hike",
		"anchors": []map[string]any{{"lon": lon0, "lat": 46.5}, {"lon": lon0 + 0.002, "lat": 46.5}},
		"legs":    []map[string]any{routeLeg(lon0)},
	}
}

func TestJourneyAPI(t *testing.T) {
	s := newTestServer(t, Limits{})
	owner := s.client(t)
	owner.do("POST", "/api/v1/auth/signup", signupBody("walker@example.ch", "walker"))
	other := s.client(t)
	other.do("POST", "/api/v1/auth/signup", signupBody("nosy@example.ch", "nosy"))
	anon := s.client(t)

	code, body := owner.do("POST", "/api/v1/journeys", map[string]any{"title": "Quer durch die Schweiz"})
	if code != http.StatusCreated {
		t.Fatalf("create: %d %s", code, body)
	}
	j := decodeJourney(t, body)
	base := "/api/v1/journeys/" + j.ID

	for _, title := range []string{"Etappe 1", "Etappe 2"} {
		code, body = owner.do("POST", base+"/stages", map[string]any{"title": title})
		if code != http.StatusOK {
			t.Fatalf("add stage: %d %s", code, body)
		}
	}
	j = decodeJourney(t, body)
	st1, st2 := j.StageList[0].ID, j.StageList[1].ID

	code, body = owner.do("POST", base+"/stages/"+st1+"/route", stageRouteBody(8.0))
	if code != http.StatusOK {
		t.Fatalf("stage route: %d %s", code, body)
	}
	if code, _ := owner.do("POST", base+"/stages/"+st1+"/route", stageRouteBody(8.0)); code != http.StatusConflict {
		t.Errorf("second route: %d", code)
	}
	code, body = owner.do("POST", base+"/stages/"+st2+"/route", stageRouteBody(8.002))
	if code != http.StatusOK {
		t.Fatalf("stage 2 route: %d %s", code, body)
	}
	j = decodeJourney(t, body)
	if j.StageList[1].Gap == nil || j.StageList[1].Gap.Status != "ok" || len(j.Profile.Breaks) != 2 {
		t.Errorf("connected stages: gap %+v, breaks %v", j.StageList[1].Gap, j.Profile.Breaks)
	}
	routePath := "/api/v1/routes/" + j.StageList[0].Route.ID

	// Stage edits: date, status, clearing the date again.
	code, body = owner.do("PATCH", base+"/stages/"+st1, map[string]any{"planned_date": "2026-10-03", "status": "done"})
	j = decodeJourney(t, body)
	if code != http.StatusOK || *j.StageList[0].PlannedDate != "2026-10-03" || j.Progress.StagesDone != 1 {
		t.Fatalf("patch stage: %d %s", code, body)
	}
	_, body = owner.do("PATCH", base+"/stages/"+st1, map[string]any{"planned_date": ""})
	if j = decodeJourney(t, body); j.StageList[0].PlannedDate != nil {
		t.Errorf("date not cleared: %v", *j.StageList[0].PlannedDate)
	}
	if code, _ := owner.do("PATCH", base+"/stages/"+st1, map[string]any{"planned_date": "3.10.2026"}); code != http.StatusUnprocessableEntity {
		t.Errorf("bad date: %d", code)
	}

	// Values that only look right are refused too, not a server error.
	for _, bad := range []map[string]any{
		{"planned_date": "2026-02-30"},
		{"done_on": "2026-13-01"},
		{"start_place_id": "------------------------------------"},
	} {
		if code, body := owner.do("PATCH", base+"/stages/"+st1, bad); code != http.StatusUnprocessableEntity {
			t.Errorf("%v: %d %s", bad, code, body)
		}
	}

	// Private: nobody else sees the journey or its stage routes.
	for _, c := range []*client{other, anon} {
		if code, _ := c.do("GET", base, nil); code != http.StatusNotFound {
			t.Errorf("private journey visible: %d", code)
		}
		if code, _ := c.do("GET", routePath, nil); code != http.StatusNotFound {
			t.Errorf("private stage route visible: %d", code)
		}
	}
	if code, _ := other.do("POST", base+"/stages", map[string]any{}); code != http.StatusNotFound {
		t.Errorf("other adds stage: %d", code)
	}
	if code, _ := owner.do("PATCH", routePath, map[string]any{"visibility": "public"}, "If-Match", `"1"`); code != http.StatusUnprocessableEntity {
		t.Errorf("stage route visibility: %d", code)
	}

	// Unlisted: the journey's link opens the journey and its stage routes.
	if _, err := s.db.Exec(context.Background(), `UPDATE users SET email_verified_at = now()`); err != nil {
		t.Fatal(err)
	}
	code, body = owner.do("PATCH", base, map[string]any{"visibility": "unlisted"}, "If-Match", `"1"`)
	j = decodeJourney(t, body)
	if code != http.StatusOK || len(j.ShareToken) != 22 {
		t.Fatalf("unlisted: %d %s", code, body)
	}
	code, body = anon.do("GET", base+"?t="+j.ShareToken, nil)
	if code != http.StatusOK || decodeJourney(t, body).CanEdit {
		t.Errorf("journey by link: %d", code)
	}
	if code, _ := anon.do("GET", routePath+"?t="+j.ShareToken, nil); code != http.StatusOK {
		t.Errorf("stage route by journey link: %d", code)
	}
	if code, _ := anon.do("GET", routePath, nil); code != http.StatusNotFound {
		t.Errorf("stage route without token: %d", code)
	}

	// GPX: one file per routed stage.
	code, body = anon.do("GET", base+"/gpx?t="+j.ShareToken, nil)
	if code != http.StatusOK {
		t.Fatalf("gpx zip: %d", code)
	}
	zr, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil || len(zr.File) != 2 || zr.File[0].Name != "01-etappe-1.gpx" {
		t.Errorf("zip: %v %d files", err, len(zr.File))
	}

	// A new link: the old one opens neither the journey nor its stages.
	if code, _ := anon.do("POST", base+"/link/rotate", nil); code != http.StatusNotFound {
		t.Errorf("rotate by someone else: %d", code)
	}
	code, body = owner.do("POST", base+"/link/rotate", nil)
	var rot struct {
		ShareToken string `json:"share_token"`
	}
	if err := json.Unmarshal(body, &rot); code != http.StatusOK || err != nil || rot.ShareToken == j.ShareToken || len(rot.ShareToken) != 22 {
		t.Fatalf("rotate: %d %s", code, body)
	}
	for _, p := range []string{base, routePath, base + "/gpx"} {
		if code, _ := anon.do("GET", p+"?t="+j.ShareToken, nil); code != http.StatusNotFound {
			t.Errorf("%s with the old link: %d", p, code)
		}
		if code, _ := anon.do("GET", p+"?t="+rot.ShareToken, nil); code != http.StatusOK {
			t.Errorf("%s with the new link: %d", p, code)
		}
	}

	// Reorder, delete a stage (and its route), delete the journey.
	_, body = owner.do("PUT", base+"/stages/order", map[string]any{"stage_ids": []string{st2, st1}})
	if j = decodeJourney(t, body); j.StageList[0].ID != st2 {
		t.Errorf("reorder: %+v", j.StageList)
	}
	_, body = owner.do("DELETE", base+"/stages/"+st1, nil)
	if j = decodeJourney(t, body); len(j.StageList) != 1 {
		t.Errorf("after delete: %d stages", len(j.StageList))
	}
	if code, _ := owner.do("GET", routePath, nil); code != http.StatusNotFound {
		t.Errorf("route of deleted stage: %d", code)
	}
	if code, _ := owner.do("DELETE", base, nil); code != http.StatusNoContent {
		t.Errorf("delete journey: %d", code)
	}
}
