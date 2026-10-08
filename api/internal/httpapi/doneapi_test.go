package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"sort"
	"strings"
	"testing"
)

func TestDone(t *testing.T) {
	s := newTestServer(t, Limits{})
	ctx := context.Background()
	signup := func(name string) *client {
		c := s.client(t)
		if code, body := c.do("POST", "/api/v1/auth/signup", signupBody(name+"@example.ch", name)); code != http.StatusCreated {
			t.Fatalf("signup %s: %d %s", name, code, body)
		}
		if _, err := s.db.Exec(ctx, `UPDATE users SET email_verified_at = now() WHERE username = $1`, name); err != nil {
			t.Fatal(err)
		}
		return c
	}
	owner, hiker := signup("owner"), signup("hiker")
	create := func(title string) string {
		_, body := owner.do("POST", "/api/v1/routes", newRouteBody(title, "public"))
		var r savedRoute
		_ = json.Unmarshal(body, &r)
		return r.ID
	}
	planned, hiked, recorded := create("Geplant"), create("Gewandert"), create("Aufgezeichnet")
	state := func(c *client, path string) (string, bool) {
		t.Helper()
		code, body := c.do("GET", path, nil)
		if code != http.StatusOK {
			t.Fatalf("GET %s: %d %s", path, code, body)
		}
		var b struct {
			DoneOn     string `json:"done_on"`
			DoneMarked bool   `json:"done_marked"`
		}
		_ = json.Unmarshal(body, &b)
		return b.DoneOn, b.DoneMarked
	}

	// Anyone who can see a route marks it, on a day up to today.
	if code, body := hiker.do("PUT", "/api/v1/routes/"+hiked+"/done", map[string]any{"done_on": "2026-08-01"}); code != http.StatusOK ||
		!strings.Contains(string(body), `"done_on":"2026-08-01"`) {
		t.Fatalf("mark: %d %s", code, body)
	}
	if on, marked := state(hiker, "/api/v1/routes/"+hiked); on != "2026-08-01" || !marked {
		t.Errorf("hiker sees %q %v", on, marked)
	}
	if on, _ := state(owner, "/api/v1/routes/"+hiked); on != "" {
		t.Errorf("a mark is the hiker's own; owner sees %q", on)
	}
	if code, _ := hiker.do("PUT", "/api/v1/routes/"+hiked+"/done", map[string]any{"done_on": "2999-01-01"}); code != http.StatusUnprocessableEntity {
		t.Errorf("future day: %d", code)
	}
	for _, kind := range []string{"routes", "journeys"} {
		if code, _ := hiker.do("PUT", "/api/v1/"+kind+"/00000000-0000-0000-0000-000000000001/done", nil); code != http.StatusNotFound {
			t.Errorf("unknown %s: %d", kind, code)
		}
	}
	if code, _ := s.client(t).do("PUT", "/api/v1/routes/"+hiked+"/done", nil); code != http.StatusUnauthorized {
		t.Errorf("anonymous: %d", code)
	}
	owner.do("PUT", "/api/v1/routes/"+hiked+"/done", nil) // today

	// A recorded hike counts without a mark and stays so.
	if _, err := s.db.Exec(ctx, `UPDATE routes SET hiked_at = '2026-09-20 07:00+02' WHERE id = $1`, recorded); err != nil {
		t.Fatal(err)
	}
	owner.do("DELETE", "/api/v1/routes/"+recorded+"/done", nil)
	if on, marked := state(owner, "/api/v1/routes/"+recorded); on != "2026-09-20" || marked {
		t.Errorf("recorded: %q %v", on, marked)
	}

	// The list and the map tell planned from hiked.
	_, body := owner.do("GET", "/api/v1/routes", nil)
	var list struct {
		Routes []struct {
			Title  string `json:"title"`
			DoneOn string `json:"done_on"`
		}
	}
	_ = json.Unmarshal(body, &list)
	var hikedTitles []string
	for _, r := range list.Routes {
		if r.DoneOn != "" {
			hikedTitles = append(hikedTitles, r.Title)
		}
	}
	sort.Strings(hikedTitles)
	if strings.Join(hikedTitles, ",") != "Aufgezeichnet,Gewandert" {
		t.Errorf("hiked in the list: %v", hikedTitles)
	}
	titles := func(filter string) string {
		_, body := owner.do("GET", "/api/v1/me/map?bbox=5.7,45.6,10.7,48"+filter, nil)
		var m struct{ Items []struct{ Title string } }
		_ = json.Unmarshal(body, &m)
		var out []string
		for _, it := range m.Items {
			out = append(out, it.Title)
		}
		sort.Strings(out)
		return strings.Join(out, ",")
	}
	if got := titles("&done=planned"); got != "Geplant" {
		t.Errorf("planned on the map: %s", got)
	}
	if got := titles("&done=done"); got != "Aufgezeichnet,Gewandert" {
		t.Errorf("hiked on the map: %s", got)
	}

	// Taking a mark back.
	if code, body := hiker.do("DELETE", "/api/v1/routes/"+hiked+"/done", nil); code != http.StatusOK || strings.Contains(string(body), "done_on") {
		t.Errorf("unmark: %d %s", code, body)
	}

	// A journey: done for its owner once no stage is left planned; a stage
	// is ticked off there, not marked on its route.
	_, body = owner.do("POST", "/api/v1/journeys", map[string]any{"title": "Via Alpina", "visibility": "public"})
	j := decodeJourney(t, body)
	if _, err := s.db.Exec(ctx, `INSERT INTO stages (journey_id, position, status, done_on, route_id)
		VALUES ($1, 0, 'done', '2026-07-01', $2), ($1, 1, 'skipped', NULL, NULL)`, j.ID, planned); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(ctx, `UPDATE routes SET journey_id = $1 WHERE id = $2`, j.ID, planned); err != nil {
		t.Fatal(err)
	}
	if on, marked := state(owner, "/api/v1/journeys/"+j.ID); on != "2026-07-01" || marked {
		t.Errorf("journey for its owner: %q %v", on, marked)
	}
	if on, _ := state(hiker, "/api/v1/journeys/"+j.ID); on != "" {
		t.Errorf("journey for someone else: %q", on)
	}
	if code, _ := hiker.do("PUT", "/api/v1/journeys/"+j.ID+"/done", nil); code != http.StatusOK {
		t.Errorf("mark a journey: %d", code)
	}
	if code, _ := owner.do("PUT", "/api/v1/routes/"+planned+"/done", nil); code != http.StatusUnprocessableEntity {
		t.Errorf("mark a stage's route: %d", code)
	}
}
