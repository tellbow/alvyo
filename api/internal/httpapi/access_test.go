package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

// TestAccessMatrix checks every actor against every action on a private
// route, a private journey and its stage route.
func TestAccessMatrix(t *testing.T) {
	s := newTestServer(t, Limits{})
	ctx := context.Background()
	verify := func(username string) {
		t.Helper()
		if _, err := s.db.Exec(ctx, `UPDATE users SET email_verified_at = now() WHERE username = $1`, username); err != nil {
			t.Fatal(err)
		}
	}
	signup := func(name string) *client {
		c := s.client(t)
		if code, body := c.do("POST", "/api/v1/auth/signup", signupBody(name+"@example.ch", name)); code != http.StatusCreated {
			t.Fatalf("signup %s: %d %s", name, code, body)
		}
		return c
	}
	owner, editor, viewer, pending, stranger := signup("owner"), signup("edi"), signup("vie"), signup("pen"), signup("str")
	anon := s.client(t)
	verify("owner")
	verify("vie")

	_, body := owner.do("POST", "/api/v1/routes", newRouteBody("Library route", "private"))
	var route struct {
		ID string `json:"id"`
	}
	_ = json.Unmarshal(body, &route)
	_, body = owner.do("POST", "/api/v1/journeys", map[string]any{"title": "Via Alpina", "visibility": "private"})
	j := decodeJourney(t, body)
	_, body = owner.do("POST", "/api/v1/journeys/"+j.ID+"/stages", map[string]any{})
	j = decodeJourney(t, body)
	stage := j.StageList[0].ID
	_, body = owner.do("POST", "/api/v1/journeys/"+j.ID+"/stages/"+stage+"/route", stageRouteBody(8.0))
	j = decodeJourney(t, body)
	stageRoute := j.StageList[0].Route.ID

	for _, item := range []string{"/api/v1/routes/" + route.ID, "/api/v1/journeys/" + j.ID} {
		for _, inv := range []map[string]any{
			{"username": "edi", "role": "editor"},
			{"email": "vie@example.ch", "role": "viewer"},
			{"email": "pen@example.ch", "role": "viewer"}, // pen's address is not verified
		} {
			if code, body := owner.do("POST", item+"/grants", inv); code != http.StatusOK {
				t.Fatalf("invite %v to %s: %d %s", inv, item, code, body)
			}
		}
	}
	if n := len(s.mail.Sent()); n != 5+6 { // 5 verification mails, 6 invitations
		t.Errorf("%d mails", n)
	}

	etag := func(path string) []string {
		code, body := owner.do("GET", path, nil)
		if code != http.StatusOK {
			t.Fatalf("etag %s: %d", path, code)
		}
		var v struct {
			Version int `json:"version"`
		}
		_ = json.Unmarshal(body, &v)
		return []string{"If-Match", `"` + strings.TrimSpace(itoa(v.Version)) + `"`}
	}

	// Columns: anonymous, stranger, pending invitee, viewer, editor, owner.
	actors := []struct {
		name string
		c    *client
	}{{"anon", anon}, {"stranger", stranger}, {"pending", pending}, {"viewer", viewer}, {"editor", editor}, {"owner", owner}}
	r, jr, sr := "/api/v1/routes/"+route.ID, "/api/v1/journeys/"+j.ID, "/api/v1/routes/"+stageRoute
	title := map[string]any{"title": "Renamed"}
	for _, tc := range []struct {
		action, method, path string
		body                 any
		ifMatch              string // path to read the version from
		want                 [6]int
	}{
		{"view route", "GET", r, nil, "", [6]int{404, 404, 404, 200, 200, 200}},
		{"download route", "GET", r + "/gpx", nil, "", [6]int{404, 404, 404, 200, 200, 200}},
		{"edit route", "PATCH", r, title, r, [6]int{404, 404, 404, 403, 200, 200}},
		{"list route grants", "GET", r + "/grants", nil, "", [6]int{404, 404, 404, 403, 403, 200}},
		{"rotate route link", "POST", r + "/link/rotate", nil, "", [6]int{404, 404, 404, 403, 403, 200}},
		{"view journey", "GET", jr, nil, "", [6]int{404, 404, 404, 200, 200, 200}},
		{"download journey", "GET", jr + "/gpx", nil, "", [6]int{404, 404, 404, 200, 200, 200}},
		{"edit stage", "PATCH", jr + "/stages/" + stage, title, "", [6]int{404, 404, 404, 403, 200, 200}},
		{"add stage", "POST", jr + "/stages", map[string]any{}, "", [6]int{404, 404, 404, 403, 200, 200}},
		{"view stage route", "GET", sr, nil, "", [6]int{404, 404, 404, 200, 200, 200}},
		{"edit stage route", "PATCH", sr, title, sr, [6]int{404, 404, 404, 403, 200, 200}},
		{"edit journey title", "PATCH", jr, title, jr, [6]int{404, 404, 404, 403, 200, 200}},
		{"tag journey", "PATCH", jr, map[string]any{"tags": []string{"Winter"}}, jr, [6]int{404, 404, 404, 403, 200, 200}},
		{"tag route", "PATCH", r, map[string]any{"tags": []string{"Winter"}}, r, [6]int{404, 404, 404, 403, 200, 200}},
		{"list journey grants", "GET", jr + "/grants", nil, "", [6]int{404, 404, 404, 403, 403, 200}},
		{"invite to journey", "POST", jr + "/grants", map[string]any{"username": "str", "role": "viewer"}, "", [6]int{404, 404, 404, 403, 403, 200}},
		{"share route by link", "PATCH", r, map[string]any{"visibility": "unlisted"}, r, [6]int{404, 404, 404, 403, 403, 200}},
		// str is a viewer of the journey from the invitation above on.
		{"share journey by link", "PATCH", jr, map[string]any{"visibility": "unlisted"}, jr, [6]int{404, 403, 404, 403, 403, 200}},
	} {
		for i, a := range actors {
			if tc.action == "invite to journey" && a.name == "stranger" {
				continue // the owner invites str in this row; checked below
			}
			var headers []string
			if tc.ifMatch != "" {
				headers = etag(tc.ifMatch)
			}
			if code, body := a.c.do(tc.method, tc.path, tc.body, headers...); code != tc.want[i] {
				t.Errorf("%s as %s: %d, want %d (%s)", tc.action, a.name, code, tc.want[i], body)
			}
		}
	}

	// The response tells the caller's role; only the owner sees the link.
	_, body = editor.do("GET", jr, nil)
	var jb struct {
		Role       string `json:"role"`
		CanEdit    bool   `json:"can_edit"`
		ShareToken string `json:"share_token"`
	}
	_ = json.Unmarshal(body, &jb)
	if jb.Role != "editor" || !jb.CanEdit || jb.ShareToken != "" {
		t.Errorf("editor's view %+v", jb)
	}

	// A stage planned by the editor belongs to the journey owner.
	_, body = editor.do("GET", jr, nil)
	j = decodeJourney(t, body)
	added := j.StageList[len(j.StageList)-1].ID
	if code, body := editor.do("POST", jr+"/stages/"+added+"/route", stageRouteBody(8.01)); code != http.StatusOK {
		t.Fatalf("editor plans a stage: %d %s", code, body)
	}
	var owners int
	if err := s.db.QueryRow(ctx, `SELECT count(DISTINCT owner_id) FROM routes WHERE journey_id = $1`, j.ID).Scan(&owners); err != nil || owners != 1 {
		t.Errorf("stage route owners: %d %v", owners, err)
	}

	// Shared with me: the editor sees both; the pending invitee nothing until verified.
	shared := func(c *client) (routes, journeys []string) {
		_, body := c.do("GET", "/api/v1/shared", nil)
		var out struct {
			Routes   []struct{ ID, Role string } `json:"routes"`
			Journeys []struct{ ID, Role string } `json:"journeys"`
		}
		_ = json.Unmarshal(body, &out)
		for _, x := range out.Routes {
			routes = append(routes, x.Role)
		}
		for _, x := range out.Journeys {
			journeys = append(journeys, x.Role)
		}
		return routes, journeys
	}
	if rs, js := shared(editor); len(rs) != 1 || rs[0] != "editor" || len(js) != 1 || js[0] != "editor" {
		t.Errorf("editor's shared list: %v %v", rs, js)
	}
	if rs, js := shared(pending); len(rs)+len(js) != 0 {
		t.Errorf("pending shared list: %v %v", rs, js)
	}
	verify("pen")
	if code, _ := pending.do("GET", jr, nil); code != http.StatusOK {
		t.Errorf("verified invitee: %d", code)
	}

	// Leaving removes one's own access.
	if code, _ := viewer.do("DELETE", jr+"/access", nil); code != http.StatusNoContent {
		t.Errorf("leave: %d", code)
	}
	if code, _ := viewer.do("GET", jr, nil); code != http.StatusNotFound {
		t.Errorf("after leaving: %d", code)
	}

	// Inviting needs a verified address and exactly one invitee.
	_, body = stranger.do("POST", "/api/v1/routes", newRouteBody("Mine", "private"))
	var own struct {
		ID string `json:"id"`
	}
	_ = json.Unmarshal(body, &own)
	if code, _ := stranger.do("POST", "/api/v1/routes/"+own.ID+"/grants", map[string]any{"username": "edi", "role": "viewer"}); code != http.StatusForbidden {
		t.Errorf("unverified inviter: %d", code)
	}
	for _, bad := range []map[string]any{
		{"role": "viewer"},
		{"username": "edi", "email": "x@example.ch", "role": "viewer"},
		{"username": "nobody", "role": "viewer"},
		{"username": "owner", "role": "viewer"},
		{"email": "not-an-address", "role": "viewer"},
	} {
		if code, body := owner.do("POST", r+"/grants", bad); code != http.StatusUnprocessableEntity {
			t.Errorf("invite %v: %d %s", bad, code, body)
		}
	}
	if code, _ := owner.do("POST", sr+"/grants", map[string]any{"username": "str", "role": "viewer"}); code != http.StatusUnprocessableEntity {
		t.Errorf("sharing a stage route: %d", code)
	}

	// Deleting stays with the owner.
	for _, a := range actors[:5] {
		want := http.StatusNotFound
		if a.name != "anon" { // str was invited, pen is verified by now
			want = http.StatusForbidden
		}
		if a.name == "viewer" {
			continue // left the journey above
		}
		if code, _ := a.c.do("DELETE", jr, nil); code != want {
			t.Errorf("delete journey as %s: %d, want %d", a.name, code, want)
		}
	}
	if code, _ := owner.do("DELETE", jr, nil); code != http.StatusNoContent {
		t.Errorf("owner deletes: %d", code)
	}
}

func itoa(n int) string {
	b, _ := json.Marshal(n)
	return string(b)
}
