package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

func TestFriends(t *testing.T) {
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
	anna, beat, carla, dora := signup("anna"), signup("beat"), signup("carla"), signup("dora")
	friend := func(c *client, method, user string) string {
		t.Helper()
		code, body := c.do(method, "/api/v1/users/"+user+"/friend", nil)
		if code != http.StatusOK {
			return http.StatusText(code)
		}
		var r struct{ Friend string }
		_ = json.Unmarshal(body, &r)
		return r.Friend
	}
	search := func(c *client, q string) string {
		t.Helper()
		code, body := c.do("GET", "/api/v1/users?q="+q, nil)
		if code != http.StatusOK {
			t.Fatalf("search %q: %d %s", q, code, body)
		}
		var r struct {
			Users []struct{ Username, Friend string }
		}
		_ = json.Unmarshal(body, &r)
		var out []string
		for _, u := range r.Users {
			out = append(out, u.Username+":"+u.Friend)
		}
		return strings.Join(out, ",")
	}
	lists := func(c *client) (friends, incoming, outgoing int) {
		t.Helper()
		_, body := c.do("GET", "/api/v1/me/friends", nil)
		var l struct{ Friends, Incoming, Outgoing []struct{ Username string } }
		_ = json.Unmarshal(body, &l)
		return len(l.Friends), len(l.Incoming), len(l.Outgoing)
	}

	// Public profiles are found, not oneself; the search needs a login.
	if got := search(anna, "be"); got != "beat:none" {
		t.Errorf("search be: %s", got)
	}
	if got := search(anna, "ann"); got != "" {
		t.Errorf("found oneself: %s", got)
	}
	if code, _ := s.client(t).do("GET", "/api/v1/users?q=be", nil); code != http.StatusUnauthorized {
		t.Errorf("anonymous search: %d", code)
	}

	// Anna asks, Beat is told and sees it, accepts: friends both ways.
	mails := len(s.mail.Sent())
	if got := friend(anna, "PUT", "beat"); got != "requested" {
		t.Fatalf("ask: %s", got)
	}
	if len(s.mail.Sent()) != mails+1 || !strings.Contains(s.mail.Sent()[mails].Text, "/friends") {
		t.Errorf("no e-mail about the request")
	}
	_, body := beat.do("GET", "/api/v1/me", nil)
	var me struct {
		FriendRequests int  `json:"friend_requests"`
		ProfilePublic  bool `json:"profile_public"`
	}
	_ = json.Unmarshal(body, &me)
	if me.FriendRequests != 1 || !me.ProfilePublic {
		t.Errorf("beat's me: %+v", me)
	}
	if f, i, o := lists(beat); f != 0 || i != 1 || o != 0 {
		t.Errorf("beat's lists: %d %d %d", f, i, o)
	}
	if got := friend(beat, "PUT", "anna"); got != "friends" {
		t.Fatalf("accept: %s", got)
	}
	if f, i, o := lists(anna); f != 1 || i != 0 || o != 0 {
		t.Errorf("anna's lists: %d %d %d", f, i, o)
	}
	if got := search(carla, "anna"); got != "anna:none" {
		t.Errorf("carla's search: %s", got)
	}

	// A private profile is not found and cannot be asked; its owner's
	// friends still see it.
	if code, _ := beat.do("PATCH", "/api/v1/me", map[string]any{"profile_public": false}); code != http.StatusOK {
		t.Fatalf("private: %d", code)
	}
	if got := search(carla, "beat"); got != "" {
		t.Errorf("private profile found: %s", got)
	}
	if got := friend(carla, "PUT", "beat"); got != http.StatusText(http.StatusNotFound) {
		t.Errorf("asking a private profile: %s", got)
	}
	if _, err := s.db.Exec(ctx, `INSERT INTO routes (owner_id, title, visibility, anchors, legs, geom, distance_m, ascent_m, descent_m,
		duration_s, duration_reverse_s, ele_min_m, ele_max_m, sac_grade, sac_max)
		SELECT id, 'Gratweg', 'public', '[]', '[]', ST_GeomFromText('LINESTRING Z (8 46 1, 8.1 46 1)', 4326), 0, 0, 0, 0, 0, 0, 0, 1, 1
		FROM users WHERE username = 'beat'`); err != nil {
		t.Fatal(err)
	}
	if code, _ := anna.do("GET", "/api/v1/users/beat", nil); code != http.StatusOK {
		t.Errorf("friend sees the private profile: %d", code)
	}
	if code, _ := carla.do("GET", "/api/v1/users/beat", nil); code != http.StatusNotFound {
		t.Errorf("stranger sees the private profile: %d", code)
	}

	// Beat's invite link: Carla becomes a friend at once; a new link ends
	// the old one.
	_, body = beat.do("GET", "/api/v1/me/friend-link", nil)
	var link struct{ Token string }
	_ = json.Unmarshal(body, &link)
	if code, body := s.client(t).do("GET", "/api/v1/friend-invites/"+link.Token, nil); code != http.StatusOK || !strings.Contains(string(body), `"beat"`) {
		t.Errorf("inviter: %d %s", code, body)
	}
	if code, _ := carla.do("POST", "/api/v1/friend-invites/"+link.Token, nil); code != http.StatusOK {
		t.Errorf("accept invite: %d", code)
	}
	if code, _ := carla.do("GET", "/api/v1/users/beat", nil); code != http.StatusOK {
		t.Errorf("invited friend sees the private profile: %d", code)
	}
	if code, _ := beat.do("POST", "/api/v1/friend-invites/"+link.Token, nil); code != http.StatusForbidden {
		t.Errorf("own link: %d", code)
	}
	beat.do("POST", "/api/v1/me/friend-link", nil)
	if code, _ := dora.do("POST", "/api/v1/friend-invites/"+link.Token, nil); code != http.StatusNotFound {
		t.Errorf("old link: %d", code)
	}

	// Blocking ends the friendship and stops requests; removing ends one.
	beat.do("PUT", "/api/v1/users/carla/block", nil)
	if got := friend(carla, "PUT", "dora"); got != "requested" {
		t.Errorf("carla asks dora: %s", got)
	}
	if f, _, _ := lists(carla); f != 0 {
		t.Errorf("friends after the block: %d", f)
	}
	if got := friend(anna, "DELETE", "beat"); got != "none" {
		t.Errorf("unfriend: %s", got)
	}
	if code, _ := dora.do("PUT", "/api/v1/users/dora/friend", nil); code != http.StatusUnprocessableEntity {
		t.Errorf("befriending oneself: %d", code)
	}
}
