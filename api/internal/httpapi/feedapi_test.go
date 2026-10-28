package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

func TestActivityFeed(t *testing.T) {
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
	me, bea, tom, mia, eve := signup("ich"), signup("bea"), signup("tom"), signup("mia"), signup("eve")
	create := func(c *client, title, visibility string) string {
		t.Helper()
		code, body := c.do("POST", "/api/v1/routes", newRouteBody(title, visibility))
		if code != http.StatusCreated {
			t.Fatalf("create %s: %d %s", title, code, body)
		}
		var r savedRoute
		_ = json.Unmarshal(body, &r)
		return r.ID
	}
	must := func(c *client, method, path string, body any) {
		t.Helper()
		if code, resp := c.do(method, path, body); code >= 300 {
			t.Fatalf("%s %s: %d %s", method, path, code, resp)
		}
	}
	// Bea, Mia and Eve are friends; Tom is only followed.
	for _, f := range []struct {
		c    *client
		name string
	}{{bea, "bea"}, {mia, "mia"}, {eve, "eve"}} {
		must(me, "PUT", "/api/v1/users/"+f.name+"/friend", nil)
		must(f.c, "PUT", "/api/v1/users/ich/friend", nil)
	}
	must(me, "PUT", "/api/v1/users/tom/follow", nil)

	tomweg := create(tom, "Tomweg", "public")
	create(bea, "Beaweg", "public")
	secret := create(bea, "Geheimweg", "private")
	if _, err := s.db.Exec(ctx, `UPDATE routes SET source = 'recorded', hiked_at = now() - interval '1 hour' WHERE id = $1`, secret); err != nil {
		t.Fatal(err)
	}
	must(bea, "PUT", "/api/v1/routes/"+tomweg+"/done", map[string]any{"done_on": "2026-08-01"})
	must(tom, "PUT", "/api/v1/routes/"+tomweg+"/done", map[string]any{"done_on": "2026-08-02"}) // not a friend
	must(mia, "PATCH", "/api/v1/me", map[string]any{"share_hikes": false})
	must(mia, "PUT", "/api/v1/routes/"+tomweg+"/done", map[string]any{"done_on": "2026-08-03"})
	create(eve, "Evesweg", "public")
	must(me, "PUT", "/api/v1/users/eve/block", nil)
	mine := create(me, "Meinweg", "public")
	must(tom, "POST", "/api/v1/routes/"+mine+"/comments", map[string]any{"body": "Wie steil ist der Grat?"})
	must(me, "POST", "/api/v1/routes/"+mine+"/comments", map[string]any{"body": "Selbst"})

	type item struct {
		Kind, Target, ID, Title, Excerpt string
		OwnerUsername                    string  `json:"owner_username"`
		DoneOn                           string  `json:"done_on"`
		DistanceM                        float64 `json:"distance_m"`
	}
	feed := func(query string) []item {
		t.Helper()
		code, body := me.do("GET", "/api/v1/feed"+query, nil)
		if code != http.StatusOK {
			t.Fatalf("feed: %d %s", code, body)
		}
		var r struct{ Items []item }
		_ = json.Unmarshal(body, &r)
		return r.Items
	}
	describe := func(items []item) string {
		var out []string
		for _, it := range items {
			out = append(out, it.Kind+":"+it.OwnerUsername+":"+it.Title)
		}
		return strings.Join(out, ",")
	}

	// Without activity as before: what the followed published.
	if got := describe(feed("")); got != "route:tom:Tomweg" {
		t.Errorf("feed: %s", got)
	}
	// Newest first. Bea's recording is hers alone: its numbers, no title or
	// id. Nothing of Mia's hike (switched off), Tom's (not a friend) or Eve
	// (blocked), nor my own comment.
	items := feed("?activity=true")
	want := "comment:tom:Meinweg,hike:bea:Tomweg,route:bea:Beaweg,route:tom:Tomweg,hike:bea:"
	if got := describe(items); got != want {
		t.Fatalf("activity:\n got %s\nwant %s", got, want)
	}
	if c := items[0]; c.Excerpt != "Wie steil ist der Grat?" || c.ID != mine || c.Target != "route" {
		t.Errorf("comment: %+v", c)
	}
	if h := items[1]; h.ID != tomweg || h.DoneOn != "2026-08-01" {
		t.Errorf("hike: %+v", h)
	}
	if h := items[4]; h.ID != "" || h.DistanceM == 0 || h.DoneOn == "" {
		t.Errorf("private hike: %+v", h)
	}
	if _, body := mia.do("GET", "/api/v1/me", nil); !strings.Contains(string(body), `"share_hikes":false`) {
		t.Errorf("me: %s", body)
	}
}
