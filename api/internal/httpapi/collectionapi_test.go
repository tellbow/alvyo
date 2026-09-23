package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
)

type collectionResp struct {
	ID       string `json:"id"`
	Version  int    `json:"version"`
	Role     string `json:"role"`
	Items    int    `json:"items"`
	ItemList []struct {
		ID       string         `json:"id"`
		Kind     string         `json:"kind"`
		TargetID string         `json:"target_id"`
		Title    string         `json:"title"`
		Note     string         `json:"note"`
		Position int            `json:"position"`
		Stages   int            `json:"stages"`
		Lines    [][][2]float64 `json:"lines"`
	} `json:"item_list"`
}

func decodeCollection(t *testing.T, code int, body []byte) collectionResp {
	t.Helper()
	var c collectionResp
	if err := json.Unmarshal(body, &c); err != nil || code >= 300 {
		t.Fatalf("%d %v: %s", code, err, body)
	}
	return c
}

func TestCollections(t *testing.T) {
	s := newTestServer(t, Limits{})
	ctx := context.Background()
	signup := func(name string) *client {
		c := s.client(t)
		c.do("POST", "/api/v1/auth/signup", signupBody(name+"@example.ch", name))
		if _, err := s.db.Exec(ctx, `UPDATE users SET email_verified_at = now() WHERE username = $1`, name); err != nil {
			t.Fatal(err)
		}
		return c
	}
	anna, bea, carl := signup("anna"), signup("bea"), signup("carl")
	dc := func(code int, body []byte) collectionResp { t.Helper(); return decodeCollection(t, code, body) }
	newRoute := func(c *client, title, visibility string) string {
		t.Helper()
		code, body := c.do("POST", "/api/v1/routes", newRouteBody(title, visibility))
		var r struct {
			ID string `json:"id"`
		}
		if err := json.Unmarshal(body, &r); err != nil || code != http.StatusCreated {
			t.Fatalf("route: %d %s", code, body)
		}
		return r.ID
	}
	annaPrivate, annaPublic := newRoute(anna, "Anna private", "private"), newRoute(anna, "Anna public", "public")
	beaPrivate := newRoute(bea, "Bea private", "private")
	_, body := anna.do("POST", "/api/v1/journeys", map[string]any{"title": "Anna journey", "visibility": "public"})
	journey := decodeJourney(t, body)
	_, body = anna.do("POST", "/api/v1/journeys/"+journey.ID+"/stages", map[string]any{})
	journey = decodeJourney(t, body)
	_, body = anna.do("POST", "/api/v1/journeys/"+journey.ID+"/stages/"+journey.StageList[0].ID+"/route", stageRouteBody(8.0))
	journey = decodeJourney(t, body)

	c := dc(anna.do("POST", "/api/v1/collections", map[string]any{"title": "Wishlist", "visibility": "public"}))
	base := "/api/v1/collections/" + c.ID
	for _, item := range []map[string]any{
		{"route_id": annaPrivate, "note": "some day"},
		{"route_id": annaPublic},
		{"journey_id": journey.ID},
	} {
		c = dc(anna.do("POST", base+"/items", item))
	}
	if len(c.ItemList) != 3 || c.ItemList[0].Note != "some day" || c.ItemList[2].Kind != "journey" ||
		c.ItemList[2].Stages != 1 || len(c.ItemList[2].Lines) != 1 || len(c.ItemList[0].Lines) != 1 {
		t.Fatalf("items %+v", c.ItemList)
	}

	for _, tc := range []struct {
		name string
		body map[string]any
		want int
	}{
		{"duplicate", map[string]any{"route_id": annaPublic}, http.StatusConflict},
		{"someone's private route", map[string]any{"route_id": beaPrivate}, http.StatusNotFound},
		{"a stage route", map[string]any{"route_id": journey.StageList[0].Route.ID}, http.StatusUnprocessableEntity},
		{"nothing", map[string]any{}, http.StatusUnprocessableEntity},
	} {
		if code, body := anna.do("POST", base+"/items", tc.body); code != tc.want {
			t.Errorf("add %s: %d, want %d (%s)", tc.name, code, tc.want, body)
		}
	}

	// The public collection does not open Anna's private route to others.
	titles := func(cl *client) []string {
		t.Helper()
		code, body := cl.do("GET", base, nil)
		col := decodeCollection(t, code, body)
		out := []string{}
		for _, it := range col.ItemList {
			out = append(out, it.Title)
		}
		return out
	}
	if got := titles(s.client(t)); len(got) != 2 || got[0] != "Anna public" {
		t.Errorf("anonymous sees %v", got)
	}

	// Bea as editor adds her private route: only she (and nobody else) sees it.
	if code, body := anna.do("POST", base+"/grants", map[string]any{"username": "bea", "role": "editor"}); code != http.StatusOK {
		t.Fatalf("invite bea: %d %s", code, body)
	}
	c = dc(bea.do("POST", base+"/items", map[string]any{"route_id": beaPrivate}))
	if c.Role != "editor" {
		t.Errorf("bea's role %q", c.Role)
	}
	if got := titles(bea); len(got) != 3 || got[2] != "Bea private" {
		t.Errorf("bea sees %v", got)
	}
	if got := titles(anna); len(got) != 3 || got[0] != "Anna private" {
		t.Errorf("anna sees %v", got)
	}
	if got := titles(carl); len(got) != 2 {
		t.Errorf("carl sees %v", got)
	}

	// Moving and removing keep positions dense.
	c = dc(anna.do("GET", base, nil))
	journeyItem := c.ItemList[2].ID
	c = dc(anna.do("PATCH", base+"/items/"+journeyItem, map[string]any{"position": 0}))
	if c.ItemList[0].Kind != "journey" || c.ItemList[1].Title != "Anna private" {
		t.Errorf("after move %+v", c.ItemList)
	}
	c = dc(anna.do("DELETE", base+"/items/"+c.ItemList[1].ID, nil))
	var positions []int
	if err := s.db.QueryRow(ctx, `SELECT array_agg(position ORDER BY position) FROM collection_items WHERE collection_id = $1`,
		c.ID).Scan(&positions); err != nil || len(positions) != 3 || positions[2] != 2 {
		t.Errorf("positions %v %v", positions, err)
	}

	// Editors change content, not visibility; viewers nothing.
	if code, _ := bea.do("PATCH", base, map[string]any{"visibility": "private"}, "If-Match", `"`+itoa(c.Version)+`"`); code != http.StatusForbidden {
		t.Errorf("editor changes visibility: %d", code)
	}
	if code, _ := carl.do("POST", base+"/items", map[string]any{"route_id": annaPublic}); code != http.StatusForbidden {
		t.Errorf("viewer adds: %d", code)
	}
	code, body := anna.do("PATCH", base, map[string]any{"visibility": "private"}, "If-Match", `"`+itoa(c.Version)+`"`)
	if code != http.StatusOK {
		t.Fatalf("owner makes private: %d %s", code, body)
	}
	if code, _ := carl.do("GET", base, nil); code != http.StatusNotFound {
		t.Errorf("private collection for a stranger: %d", code)
	}

	// Shared with Bea; deleting the collection keeps the routes.
	_, body = bea.do("GET", "/api/v1/shared", nil)
	var shared struct {
		Collections []struct{ ID, Role string } `json:"collections"`
	}
	_ = json.Unmarshal(body, &shared)
	if len(shared.Collections) != 1 || shared.Collections[0].Role != "editor" {
		t.Errorf("bea's shared collections %+v", shared.Collections)
	}
	if code, _ := bea.do("DELETE", base, nil); code != http.StatusForbidden {
		t.Errorf("editor deletes: %d", code)
	}
	if code, _ := anna.do("DELETE", base, nil); code != http.StatusNoContent {
		t.Errorf("owner deletes: %d", code)
	}
	if code, _ := bea.do("GET", "/api/v1/routes/"+beaPrivate, nil); code != http.StatusOK {
		t.Errorf("route after deleting the collection: %d", code)
	}
}
