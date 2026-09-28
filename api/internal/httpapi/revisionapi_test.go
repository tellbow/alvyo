package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
)

func TestRouteRevisions(t *testing.T) {
	s := newTestServer(t, Limits{})
	signup := func(name string) *client {
		c := s.client(t)
		c.do("POST", "/api/v1/auth/signup", signupBody(name+"@example.ch", name))
		if _, err := s.db.Exec(context.Background(), `UPDATE users SET email_verified_at = now() WHERE username = $1`, name); err != nil {
			t.Fatal(err)
		}
		return c
	}
	owner, editor, viewer := signup("owner"), signup("edi"), signup("vie")
	_, body := owner.do("POST", "/api/v1/routes", newRouteBody("Grat", "private"))
	var r savedRoute
	_ = json.Unmarshal(body, &r)
	base := "/api/v1/routes/" + r.ID
	owner.do("POST", base+"/grants", map[string]any{"username": "edi", "role": "editor"})
	owner.do("POST", base+"/grants", map[string]any{"username": "vie", "role": "viewer"})

	// The editor makes it longer.
	longer := map[string]any{
		"anchors": []map[string]any{{"lon": 8.0, "lat": 46.5}, {"lon": 8.002, "lat": 46.5}, {"lon": 8.004, "lat": 46.5}, {"lon": 8.006, "lat": 46.5}},
		"legs":    []map[string]any{routeLeg(8.0), routeLeg(8.002), routeLeg(8.004)},
	}
	code, body := editor.do("PATCH", base, longer, "If-Match", `"1"`)
	if code != http.StatusOK {
		t.Fatalf("save: %d %s", code, body)
	}
	_ = json.Unmarshal(body, &r)

	if code, _ := viewer.do("GET", base+"/revisions", nil); code != http.StatusForbidden {
		t.Errorf("viewer lists: %d", code)
	}
	var list struct {
		Revisions []struct {
			Version   int    `json:"version"`
			SavedBy   string `json:"saved_by"`
			DistanceM int    `json:"distance_m"`
		} `json:"revisions"`
	}
	code, body = editor.do("GET", base+"/revisions", nil)
	if err := json.Unmarshal(body, &list); code != http.StatusOK || err != nil || len(list.Revisions) != 1 {
		t.Fatalf("list: %d %s", code, body)
	}
	if rv := list.Revisions[0]; rv.Version != 1 || rv.SavedBy != "owner" {
		t.Errorf("revision: %+v", rv)
	}

	var old struct {
		Route    savedRoute `json:"route"`
		Revision struct {
			Version int `json:"version"`
		} `json:"revision"`
	}
	code, body = owner.do("GET", base+"/revisions/1", nil)
	if err := json.Unmarshal(body, &old); code != http.StatusOK || err != nil || len(old.Route.Legs) != 2 || old.Revision.Version != 1 {
		t.Fatalf("revision 1: %d %.300s", code, body)
	}
	if old.Route.Totals.DistanceM >= r.Totals.DistanceM {
		t.Errorf("totals of the old line: %.0f, now %.0f", old.Route.Totals.DistanceM, r.Totals.DistanceM)
	}
	if code, _ := owner.do("GET", base+"/revisions/2", nil); code != http.StatusNotFound {
		t.Errorf("the current version: %d", code)
	}

	// Restoring needs the current version, and keeps the line it replaces.
	if code, _ := owner.do("POST", base+"/revisions/1/restore", nil, "If-Match", `"1"`); code != http.StatusPreconditionFailed {
		t.Errorf("stale restore: %d", code)
	}
	if code, _ := viewer.do("POST", base+"/revisions/1/restore", nil, "If-Match", `"2"`); code != http.StatusForbidden {
		t.Errorf("viewer restores: %d", code)
	}
	code, body = owner.do("POST", base+"/revisions/1/restore", nil, "If-Match", `"2"`)
	var restored savedRoute
	if err := json.Unmarshal(body, &restored); code != http.StatusOK || err != nil || len(restored.Legs) != 2 || restored.Version != 3 {
		t.Fatalf("restore: %d %.300s", code, body)
	}
	_, body = owner.do("GET", base+"/revisions", nil)
	_ = json.Unmarshal(body, &list)
	if len(list.Revisions) != 2 || list.Revisions[0].Version != 2 || list.Revisions[0].SavedBy != "edi" {
		t.Errorf("after restoring: %s", body)
	}
}
