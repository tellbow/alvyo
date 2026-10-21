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
	Hidden   int    `json:"hidden"`
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
		s.signup(c, name+"@example.ch", name)
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

	// The public collection shares Anna's private route: she added it.
	titles := func(cl *client) ([]string, int) {
		t.Helper()
		code, body := cl.do("GET", base, nil)
		col := decodeCollection(t, code, body)
		out := []string{}
		for _, it := range col.ItemList {
			out = append(out, it.Title)
		}
		return out, col.Hidden
	}
	if got, hidden := titles(s.client(t)); len(got) != 3 || got[0] != "Anna private" || hidden != 0 {
		t.Errorf("anonymous sees %v, %d hidden", got, hidden)
	}

	// Bea as editor adds her private route: everyone sees it. Carl's route,
	// only shared with Bea, she cannot pass on.
	if code, body := anna.do("POST", base+"/grants", map[string]any{"username": "bea", "role": "editor"}); code != http.StatusOK {
		t.Fatalf("invite bea: %d %s", code, body)
	}
	carlPrivate := newRoute(carl, "Carl private", "private")
	if code, body := carl.do("POST", "/api/v1/routes/"+carlPrivate+"/grants", map[string]any{"username": "bea", "role": "viewer"}); code != http.StatusOK {
		t.Fatalf("carl invites bea: %d %s", code, body)
	}
	c = dc(bea.do("POST", base+"/items", map[string]any{"route_id": beaPrivate}))
	if c.Role != "editor" {
		t.Errorf("bea's role %q", c.Role)
	}
	dc(bea.do("POST", base+"/items", map[string]any{"route_id": carlPrivate}))
	if got, hidden := titles(bea); len(got) != 5 || got[3] != "Bea private" || hidden != 0 {
		t.Errorf("bea sees %v, %d hidden", got, hidden)
	}
	if got, hidden := titles(anna); len(got) != 4 || got[0] != "Anna private" || hidden != 1 {
		t.Errorf("anna sees %v, %d hidden", got, hidden)
	}
	if got, _ := titles(carl); len(got) != 5 {
		t.Errorf("carl sees %v", got)
	}
	if code, _ := anna.do("GET", "/api/v1/routes/"+carlPrivate+"?t=c."+c.ID, nil); code != http.StatusNotFound {
		t.Errorf("anna opens carl's route through the collection: %d", code)
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
		c.ID).Scan(&positions); err != nil || len(positions) != 4 || positions[3] != 3 {
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

// Deleting a route deletes its items too; the positions behind them close
// up, also when one delete takes several (issue 29).
func TestCollectionDeletedRoutes(t *testing.T) {
	s := newTestServer(t, Limits{})
	ctx := context.Background()
	anna := s.client(t)
	s.signup(anna, "anna@example.ch", "anna")
	dc := func(code int, body []byte) collectionResp { t.Helper(); return decodeCollection(t, code, body) }
	var ids []string
	for i := range 6 {
		code, body := anna.do("POST", "/api/v1/routes", newRouteBody("R"+itoa(i), "private"))
		var r struct {
			ID string `json:"id"`
		}
		if err := json.Unmarshal(body, &r); err != nil || code != http.StatusCreated {
			t.Fatalf("route: %d %s", code, body)
		}
		ids = append(ids, r.ID)
	}
	c := dc(anna.do("POST", "/api/v1/collections", map[string]any{"title": "Wishlist"}))
	base := "/api/v1/collections/" + c.ID
	for _, id := range ids[:5] {
		dc(anna.do("POST", base+"/items", map[string]any{"route_id": id}))
	}

	if code, body := anna.do("DELETE", "/api/v1/routes/"+ids[1], nil); code != http.StatusNoContent {
		t.Fatalf("delete route: %d %s", code, body)
	}
	if _, err := s.db.Exec(ctx, `DELETE FROM routes WHERE id = ANY($1::uuid[])`, []string{ids[2], ids[4]}); err != nil {
		t.Fatal(err)
	}
	c = dc(anna.do("POST", base+"/items", map[string]any{"route_id": ids[5]}))
	var titles []string
	for i, it := range c.ItemList {
		titles = append(titles, it.Title)
		if it.Position != i {
			t.Errorf("item %d at position %d", i, it.Position)
		}
	}
	if len(titles) != 3 || titles[0] != "R0" || titles[1] != "R3" || titles[2] != "R5" {
		t.Errorf("items %v", titles)
	}
	c = dc(anna.do("PATCH", base+"/items/"+c.ItemList[2].ID, map[string]any{"position": 1}))
	if c.ItemList[1].Title != "R5" || c.ItemList[2].Title != "R3" {
		t.Errorf("after move %+v", c.ItemList)
	}
}

func TestCollectionLink(t *testing.T) {
	s := newTestServer(t, Limits{})
	anna, anon := s.client(t), s.client(t)
	s.signup(anna, "anna@example.ch", "anna")
	if _, err := s.db.Exec(context.Background(), `UPDATE users SET email_verified_at = now()`); err != nil {
		t.Fatal(err)
	}
	code, body := anna.do("POST", "/api/v1/collections", map[string]any{"title": "Herbst", "visibility": "unlisted"})
	var c struct {
		ID         string `json:"id"`
		ShareToken string `json:"share_token"`
	}
	if err := json.Unmarshal(body, &c); code != http.StatusCreated || err != nil || c.ShareToken == "" {
		t.Fatalf("create: %d %s", code, body)
	}
	base := "/api/v1/collections/" + c.ID
	if code, _ := anon.do("GET", base, nil); code != http.StatusNotFound {
		t.Errorf("without the link: %d", code)
	}
	if code, _ := anon.do("GET", base+"?t="+c.ShareToken, nil); code != http.StatusOK {
		t.Errorf("with the link: %d", code)
	}
	if code, _ := anon.do("POST", base+"/link/rotate", nil); code != http.StatusNotFound {
		t.Errorf("rotate by someone else: %d", code)
	}
	code, body = anna.do("POST", base+"/link/rotate", nil)
	var rot struct {
		ShareToken string `json:"share_token"`
	}
	if err := json.Unmarshal(body, &rot); code != http.StatusOK || err != nil || rot.ShareToken == c.ShareToken {
		t.Fatalf("rotate: %d %s", code, body)
	}
	if code, _ := anon.do("GET", base+"?t="+c.ShareToken, nil); code != http.StatusNotFound {
		t.Errorf("with the old link: %d", code)
	}
	if code, _ := anon.do("GET", base+"?t="+rot.ShareToken, nil); code != http.StatusOK {
		t.Errorf("with the new link: %d", code)
	}
}

// TestCollectionShares checks the routes and journeys a collection shares:
// with its invited people in their role, by link as viewer.
func TestCollectionShares(t *testing.T) {
	s := newTestServer(t, Limits{})
	signup := func(name string) *client {
		c := s.client(t)
		s.signup(c, name+"@example.ch", name)
		if _, err := s.db.Exec(context.Background(), `UPDATE users SET email_verified_at = now() WHERE username = $1`, name); err != nil {
			t.Fatal(err)
		}
		return c
	}
	anna, bea, carl, anon := signup("anna"), signup("bea"), signup("carl"), s.client(t)
	dc := func(code int, body []byte) collectionResp { t.Helper(); return decodeCollection(t, code, body) }
	code, body := anna.do("POST", "/api/v1/routes", newRouteBody("Anna private", "private"))
	var route struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(body, &route); err != nil || code != http.StatusCreated {
		t.Fatalf("route: %d %s", code, body)
	}
	_, body = anna.do("POST", "/api/v1/journeys", map[string]any{"title": "Anna journey", "visibility": "private"})
	journey := decodeJourney(t, body)
	_, body = anna.do("POST", "/api/v1/journeys/"+journey.ID+"/stages", map[string]any{})
	journey = decodeJourney(t, body)
	_, body = anna.do("POST", "/api/v1/journeys/"+journey.ID+"/stages/"+journey.StageList[0].ID+"/route", stageRouteBody(8.0))
	journey = decodeJourney(t, body)

	code, body = anna.do("POST", "/api/v1/collections", map[string]any{"title": "Herbst", "visibility": "unlisted"})
	var col struct {
		ID         string `json:"id"`
		ShareToken string `json:"share_token"`
	}
	if err := json.Unmarshal(body, &col); err != nil || code != http.StatusCreated {
		t.Fatalf("collection: %d %s", code, body)
	}
	base := "/api/v1/collections/" + col.ID
	c := dc(anna.do("POST", base+"/items", map[string]any{"route_id": route.ID}))
	routeItem := c.ItemList[0].ID
	dc(anna.do("POST", base+"/items", map[string]any{"journey_id": journey.ID}))
	for _, invite := range []map[string]any{{"username": "bea", "role": "viewer"}, {"username": "carl", "role": "editor"}} {
		if code, body := anna.do("POST", base+"/grants", invite); code != http.StatusOK {
			t.Fatalf("invite: %d %s", code, body)
		}
	}

	// role opens path as cl; "" when it is not found.
	role := func(cl *client, path string) string {
		t.Helper()
		code, body := cl.do("GET", path, nil)
		if code == http.StatusNotFound {
			return ""
		}
		var r struct {
			Role string `json:"role"`
		}
		if err := json.Unmarshal(body, &r); err != nil || code != http.StatusOK {
			t.Fatalf("GET %s: %d %s", path, code, body)
		}
		return r.Role
	}
	routePath, journeyPath := "/api/v1/routes/"+route.ID, "/api/v1/journeys/"+journey.ID
	stagePath := "/api/v1/routes/" + journey.StageList[0].Route.ID
	pass := "?t=c." + col.ID + "." + col.ShareToken
	for _, tc := range []struct {
		name string
		cl   *client
		path string
		want string
	}{
		{"anonymous without the link", anon, routePath, ""},
		{"anonymous with the collection only", anon, routePath + "?t=c." + col.ID, ""},
		{"anonymous with a wrong token", anon, routePath + "?t=c." + col.ID + ".wrong", ""},
		{"anonymous with the link", anon, routePath + pass, "viewer"},
		{"anonymous, the journey", anon, journeyPath + pass, "viewer"},
		{"anonymous, a stage", anon, stagePath + pass, "viewer"},
		{"invited viewer", bea, routePath, "viewer"},
		{"invited editor", carl, routePath, "editor"},
		{"invited editor with the link", carl, routePath + pass, "editor"},
		{"invited editor, the journey", carl, journeyPath, "editor"},
		{"invited editor, a stage", carl, stagePath, "editor"},
	} {
		if got := role(tc.cl, tc.path); got != tc.want {
			t.Errorf("%s: role %q, want %q", tc.name, got, tc.want)
		}
	}

	// Editors change the route, not its visibility; viewers nothing.
	match := func() []string {
		_, body := anna.do("GET", routePath, nil)
		var r struct {
			Version int `json:"version"`
		}
		_ = json.Unmarshal(body, &r)
		return []string{"If-Match", `"` + itoa(r.Version) + `"`}
	}
	if code, _ := bea.do("PATCH", routePath, map[string]any{"title": "Bea's"}, match()...); code != http.StatusForbidden {
		t.Errorf("viewer changes the route: %d", code)
	}
	if code, body := carl.do("PATCH", routePath, map[string]any{"title": "Carl's"}, match()...); code != http.StatusOK {
		t.Errorf("editor changes the route: %d %s", code, body)
	}
	if code, _ := carl.do("PATCH", routePath, map[string]any{"visibility": "public"}, match()...); code != http.StatusForbidden {
		t.Errorf("editor changes the visibility: %d", code)
	}

	// Taken out of the collection, the route is Anna's alone again.
	dc(anna.do("DELETE", base+"/items/"+routeItem, nil))
	if got := role(carl, routePath); got != "" {
		t.Errorf("editor after removing: %q", got)
	}
	if got := role(anon, routePath+pass); got != "" {
		t.Errorf("link after removing: %q", got)
	}
}
