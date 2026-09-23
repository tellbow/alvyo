package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

type socialResp struct {
	Likes           int  `json:"likes"`
	Liked           bool `json:"liked"`
	CommentsEnabled bool `json:"comments_enabled"`
	CanComment      bool `json:"can_comment"`
	CanModerate     bool `json:"can_moderate"`
	Comments        []struct {
		ID             string `json:"id"`
		AuthorUsername string `json:"author_username"`
		Body           string `json:"body"`
		CanDelete      bool   `json:"can_delete"`
	} `json:"comments"`
}

func (c *client) social(method, path string, body any) (int, socialResp) {
	c.t.Helper()
	code, raw := c.do(method, path, body)
	var s socialResp
	_ = json.Unmarshal(raw, &s)
	return code, s
}

func (s socialResp) authors() string {
	var a []string
	for _, c := range s.Comments {
		a = append(a, c.AuthorUsername)
	}
	return strings.Join(a, ",")
}

func TestCommunity(t *testing.T) {
	s := newTestServer(t, Limits{})
	ctx := context.Background()
	signup := func(name string, verified bool) *client {
		c := s.client(t)
		if code, body := c.do("POST", "/api/v1/auth/signup", signupBody(name+"@example.ch", name)); code != http.StatusCreated {
			t.Fatalf("signup %s: %d %s", name, code, body)
		}
		if verified {
			if _, err := s.db.Exec(ctx, `UPDATE users SET email_verified_at = now() WHERE username = $1`, name); err != nil {
				t.Fatal(err)
			}
		}
		return c
	}
	owner, fan, troll, mod := signup("owner", true), signup("fan", true), signup("troll", true), signup("mod", true)
	unverified, anon := signup("newbie", false), s.client(t)
	if _, err := s.db.Exec(ctx, `UPDATE users SET role = 'moderator' WHERE username = 'mod'`); err != nil {
		t.Fatal(err)
	}
	mails := func() int { return len(s.mail.Sent()) }
	signupMails := mails()

	_, body := owner.do("POST", "/api/v1/routes", newRouteBody("Gratweg", "public"))
	var route savedRoute
	_ = json.Unmarshal(body, &route)
	_, body = owner.do("POST", "/api/v1/routes", newRouteBody("Geheim", "private"))
	var private savedRoute
	_ = json.Unmarshal(body, &private)
	_, body = owner.do("POST", "/api/v1/journeys", map[string]any{"title": "Via Alpina", "visibility": "unlisted"})
	journey := decodeJourney(t, body)
	r := "/api/v1/routes/" + route.ID
	j := "/api/v1/journeys/" + journey.ID

	// Anyone who can see an item sees its likes and comments.
	if code, sc := anon.social("GET", r+"/social", nil); code != http.StatusOK || sc.Likes != 0 || sc.CanComment || !sc.CommentsEnabled {
		t.Fatalf("anonymous social: %d %+v", code, sc)
	}
	if code, _ := fan.social("GET", "/api/v1/routes/"+private.ID+"/social", nil); code != http.StatusNotFound {
		t.Errorf("private route social: %d, want 404", code)
	}
	if code, _ := fan.social("GET", j+"/social", nil); code != http.StatusNotFound {
		t.Errorf("unlisted journey without token: %d, want 404", code)
	}

	// Likes.
	if code, _ := anon.social("PUT", r+"/like", nil); code != http.StatusUnauthorized {
		t.Errorf("anonymous like: %d", code)
	}
	fan.social("PUT", r+"/like", nil)
	if _, sc := fan.social("PUT", r+"/like", nil); sc.Likes != 1 || !sc.Liked {
		t.Errorf("liked twice: %+v", sc)
	}
	if _, sc := fan.social("DELETE", r+"/like", nil); sc.Likes != 0 || sc.Liked {
		t.Errorf("unliked: %+v", sc)
	}

	// Comments; the owner gets one e-mail per 15 minutes and item.
	comment := func(c *client, path, text string) (int, socialResp) {
		return c.social("POST", path+"/comments", map[string]any{"body": text})
	}
	if code, _ := comment(anon, r, "Hallo"); code != http.StatusUnauthorized {
		t.Errorf("anonymous comment: %d", code)
	}
	if code, _ := comment(unverified, r, "Hallo"); code != http.StatusForbidden {
		t.Errorf("unverified comment: %d, want 403", code)
	}
	if code, _ := comment(fan, r, "   "); code != http.StatusUnprocessableEntity {
		t.Errorf("blank comment: %d, want 422", code)
	}
	code, sc := comment(fan, r, "Schöne Tour!")
	if code != http.StatusOK || len(sc.Comments) != 1 || sc.Comments[0].Body != "Schöne Tour!" || !sc.Comments[0].CanDelete || sc.CanModerate {
		t.Fatalf("comment: %d %+v", code, sc)
	}
	sent := s.mail.Sent()
	if len(sent) != signupMails+1 || sent[len(sent)-1].To != "owner@example.ch" ||
		sent[len(sent)-1].Subject != "Test User hat «Gratweg» kommentiert" || !strings.Contains(sent[len(sent)-1].Text, "Schöne Tour!") {
		t.Fatalf("comment mail: %+v", sent[len(sent)-1])
	}
	comment(troll, r, "Spam spam spam")
	if mails() != signupMails+1 {
		t.Errorf("a second comment within 15 minutes sent another e-mail")
	}
	comment(owner, r, "Danke!")
	if _, sc := anon.social("GET", r+"/social", nil); sc.authors() != "fan,troll,owner" || sc.Comments[0].CanDelete {
		t.Errorf("comments seen by anonymous: %+v", sc)
	}

	// With the link, the unlisted journey can be commented on.
	if code, _ := fan.social("POST", j+"/comments?t="+journey.ShareToken, map[string]any{"body": "Mit Link"}); code != http.StatusOK {
		t.Errorf("comment with share link: %d", code)
	}

	// Blocking: the troll can no longer comment on the owner's items, and the
	// owner no longer sees the troll's comments; others still do.
	if _, rel := owner.do("PUT", "/api/v1/users/troll/block", nil); !strings.Contains(string(rel), `"blocked":true`) {
		t.Fatalf("block: %s", rel)
	}
	if code, _ := comment(troll, r, "Noch mehr"); code != http.StatusForbidden {
		t.Errorf("blocked comment: %d, want 403", code)
	}
	if _, sc := troll.social("GET", r+"/social", nil); sc.CanComment {
		t.Error("a blocked user is offered to comment")
	}
	if _, sc := owner.social("GET", r+"/social", nil); sc.authors() != "fan,owner" || !sc.CanModerate {
		t.Errorf("owner after blocking: %+v", sc)
	}
	_, sc = fan.social("GET", r+"/social", nil)
	if sc.authors() != "fan,troll,owner" {
		t.Errorf("fan after the owner blocked the troll: %s", sc.authors())
	}
	trollComment := sc.Comments[1].ID
	if code, _ := fan.social("DELETE", r+"/comments/"+trollComment, nil); code != http.StatusForbidden {
		t.Errorf("fan deletes someone else's comment: %d, want 403", code)
	}
	if _, body := owner.do("GET", "/api/v1/me/blocks", nil); !strings.Contains(string(body), `"username":"troll"`) {
		t.Errorf("block list: %s", body)
	}

	// Comments switched off: hidden and closed, except for the owner.
	owner.social("PATCH", r+"/social", map[string]any{"comments_enabled": false})
	if code, _ := comment(fan, r, "Zu spät"); code != http.StatusForbidden {
		t.Errorf("comment while off: %d, want 403", code)
	}
	if _, sc := fan.social("GET", r+"/social", nil); len(sc.Comments) != 0 || sc.CanComment {
		t.Errorf("fan while off: %+v", sc)
	}
	if code, _ := fan.social("PATCH", r+"/social", map[string]any{"comments_enabled": true}); code != http.StatusForbidden {
		t.Errorf("fan switches comments: %d, want 403", code)
	}
	owner.social("PATCH", r+"/social", map[string]any{"comments_enabled": true})

	// Reports and moderation: removing deletes the comment and closes all
	// reports on it.
	report := func(c *client, body map[string]any) int {
		code, _ := c.do("POST", "/api/v1/reports", body)
		return code
	}
	if code := report(fan, map[string]any{"kind": "comment", "id": trollComment, "reason": "spam"}); code != http.StatusNoContent {
		t.Fatalf("report: %d", code)
	}
	report(fan, map[string]any{"kind": "comment", "id": trollComment, "reason": "spam"})
	report(owner, map[string]any{"kind": "comment", "id": trollComment, "reason": "offensive", "note": "immer wieder"})
	if code := report(fan, map[string]any{"kind": "route", "id": private.ID, "reason": "spam"}); code != http.StatusNotFound {
		t.Errorf("report of a private route: %d, want 404", code)
	}
	if code, _ := fan.do("GET", "/api/v1/moderation/reports", nil); code != http.StatusForbidden {
		t.Errorf("fan reads reports: %d, want 403", code)
	}
	var queue struct {
		Reports []struct {
			ID       string `json:"id"`
			Excerpt  string `json:"excerpt"`
			Subject  string `json:"subject"`
			Reports  int    `json:"reports"`
			ItemKind string `json:"item_kind"`
			ItemID   string `json:"item_id"`
		} `json:"reports"`
	}
	_, body = mod.do("GET", "/api/v1/moderation/reports", nil)
	_ = json.Unmarshal(body, &queue)
	if len(queue.Reports) != 2 || queue.Reports[0].Excerpt != "Spam spam spam" || queue.Reports[0].Subject != "troll" ||
		queue.Reports[0].Reports != 2 || queue.Reports[0].ItemKind != "route" || queue.Reports[0].ItemID != route.ID {
		t.Fatalf("queue: %s", body)
	}
	if code, _ := mod.do("POST", "/api/v1/moderation/reports/"+queue.Reports[0].ID+"/resolve", map[string]any{"resolution": "removed"}); code != http.StatusNoContent {
		t.Fatalf("resolve: %d", code)
	}
	if _, sc := fan.social("GET", r+"/social", nil); sc.authors() != "fan,owner" {
		t.Errorf("after removal: %s", sc.authors())
	}
	_, body = mod.do("GET", "/api/v1/moderation/reports", nil)
	if !strings.Contains(string(body), `"reports":[]`) {
		t.Errorf("queue after resolving: %s", body)
	}

	// Following: the owner gets an e-mail, the fan's feed shows public items.
	before := mails()
	if _, body := fan.do("PUT", "/api/v1/users/owner/follow", nil); !strings.Contains(string(body), `"followers":1`) {
		t.Fatalf("follow: %s", body)
	}
	if mails() != before+1 || s.mail.Sent()[before].Subject != "Test User folgt dir jetzt" {
		t.Errorf("follow mail: %d mails", mails()-before)
	}
	if code, _ := troll.do("PUT", "/api/v1/users/owner/follow", nil); code != http.StatusForbidden {
		t.Errorf("blocked user follows: %d, want 403", code)
	}
	if code, _ := fan.do("PUT", "/api/v1/users/fan/follow", nil); code != http.StatusUnprocessableEntity {
		t.Errorf("follow yourself: %d, want 422", code)
	}
	_, body = fan.do("GET", "/api/v1/users/owner", nil)
	if !strings.Contains(string(body), `"followed":true`) || !strings.Contains(string(body), `"self":false`) {
		t.Errorf("profile for a follower: %s", body)
	}
	owner.do("POST", "/api/v1/routes", newRouteBody("Neu", "public"))
	var feed struct {
		Items []struct {
			Title string `json:"title"`
			Kind  string `json:"kind"`
		} `json:"items"`
	}
	_, body = fan.do("GET", "/api/v1/feed", nil)
	_ = json.Unmarshal(body, &feed)
	if len(feed.Items) != 2 || feed.Items[0].Title != "Neu" || feed.Items[1].Title != "Gratweg" {
		t.Errorf("feed: %s", body)
	}

	// Without notifications, no e-mail.
	owner.do("PATCH", "/api/v1/me", map[string]any{"notify_comments": false, "locale": "fr"})
	_, body = owner.do("GET", "/api/v1/me", nil)
	if !strings.Contains(string(body), `"notify_comments":false`) || !strings.Contains(string(body), `"notify_follows":true`) ||
		!strings.Contains(string(body), `"locale":"fr"`) {
		t.Errorf("notification settings: %s", body)
	}
	before = mails()
	fan.social("POST", j+"/comments?t="+journey.ShareToken, map[string]any{"body": "Noch einer"})
	if mails() != before {
		t.Error("e-mail sent although switched off")
	}

	// Reporting a user and removing bans them.
	report(fan, map[string]any{"kind": "user", "username": "troll", "reason": "spam"})
	_, body = mod.do("GET", "/api/v1/moderation/reports", nil)
	_ = json.Unmarshal(body, &queue)
	mod.do("POST", "/api/v1/moderation/reports/"+queue.Reports[0].ID+"/resolve", map[string]any{"resolution": "removed"})
	var banned bool
	_ = s.db.QueryRow(ctx, `SELECT banned_at IS NOT NULL FROM users WHERE username = 'troll'`).Scan(&banned)
	if !banned {
		t.Error("the reported user was not banned")
	}
}
