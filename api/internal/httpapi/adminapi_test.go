package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

// The admin portal (feedback issues 70, 72): find people and items, act on
// them, and undo from «Verlauf».
func TestAdminPortal(t *testing.T) {
	s := newTestServer(t, Limits{})
	ctx := context.Background()
	signup := func(name, role string) *client {
		c := s.client(t)
		s.signup(c, name+"@example.ch", name)
		if _, err := s.db.Exec(ctx, `UPDATE users SET role = $2, email_verified_at = now() WHERE username = $1`, name, role); err != nil {
			t.Fatal(err)
		}
		return c
	}
	mod, adm, troll := signup("mod", "moderator"), signup("adm", "admin"), signup("troll", "user")
	m, a := s.onAdmin(mod), s.onAdmin(adm)
	_, body := troll.do("POST", "/api/v1/routes", lineRoute("Werbung", "public", 8.0, 46.6, "T2"))
	var route savedRoute
	_ = json.Unmarshal(body, &route)

	visibility := func() string {
		var v string
		if err := s.db.QueryRow(ctx, `SELECT visibility FROM routes WHERE id = $1`, route.ID).Scan(&v); err != nil {
			t.Fatal(err)
		}
		return v
	}
	var users struct {
		Users []struct {
			ID, Username, Role string
			Routes             int
		} `json:"users"`
	}
	_, body = m.do("GET", "/admin-api/v1/admin/users?q=TRO", nil)
	_ = json.Unmarshal(body, &users)
	if len(users.Users) != 1 || users.Users[0].Username != "troll" || users.Users[0].Routes != 1 {
		t.Fatalf("users: %s", body)
	}
	trollID := users.Users[0].ID
	if code, _ := mod.do("GET", "/api/v1/admin/users", nil); code != http.StatusNotFound {
		t.Errorf("admin users on the public API: %d, want 404", code)
	}
	if code, _ := s.onAdmin(troll).do("GET", "/admin-api/v1/admin/users", nil); code != http.StatusForbidden {
		t.Errorf("a user lists users: %d, want 403", code)
	}

	// Banning makes the route private; undo shares it again.
	var done struct {
		LogID string `json:"log_id"`
	}
	code, body := m.do("POST", "/admin-api/v1/admin/users/"+trollID+"/ban", nil)
	_ = json.Unmarshal(body, &done)
	if code != http.StatusOK || visibility() != "private" {
		t.Fatalf("ban: %d %s, route %s", code, body, visibility())
	}
	if code, _ := troll.do("GET", "/api/v1/me", nil); code != http.StatusUnauthorized {
		t.Errorf("banned troll still logged in: %d", code)
	}
	if code, _ := m.do("POST", "/admin-api/v1/admin/users/"+trollID+"/ban", nil); code != http.StatusConflict {
		t.Errorf("ban twice: %d, want 409", code)
	}
	if code, body := m.do("POST", "/admin-api/v1/admin/log/"+done.LogID+"/undo", nil); code != http.StatusNoContent {
		t.Fatalf("undo ban: %d %s", code, body)
	}
	if visibility() != "public" {
		t.Errorf("after undoing the ban: %s", visibility())
	}
	if code, _ := m.do("POST", "/admin-api/v1/admin/log/"+done.LogID+"/undo", nil); code != http.StatusConflict {
		t.Errorf("undo twice: %d, want 409", code)
	}

	// Staff is not banned; roles are the admins'.
	var admID string
	_ = s.db.QueryRow(ctx, `SELECT id FROM users WHERE username = 'adm'`).Scan(&admID)
	if code, _ := m.do("POST", "/admin-api/v1/admin/users/"+admID+"/ban", nil); code != http.StatusForbidden {
		t.Errorf("ban an admin: %d, want 403", code)
	}
	if code, _ := m.do("PUT", "/admin-api/v1/admin/users/"+trollID+"/role", map[string]any{"role": "moderator"}); code != http.StatusForbidden {
		t.Errorf("moderator sets a role: %d, want 403", code)
	}
	if code, _ := a.do("PUT", "/admin-api/v1/admin/users/"+admID+"/role", map[string]any{"role": "user"}); code != http.StatusUnprocessableEntity {
		t.Errorf("admin demotes themselves: %d, want 422", code)
	}
	_, body = a.do("PUT", "/admin-api/v1/admin/users/"+trollID+"/role", map[string]any{"role": "moderator"})
	_ = json.Unmarshal(body, &done)
	if code, _ := m.do("POST", "/admin-api/v1/admin/log/"+done.LogID+"/undo", nil); code != http.StatusForbidden {
		t.Errorf("moderator undoes a role: %d, want 403", code)
	}
	if code, _ := a.do("POST", "/admin-api/v1/admin/log/"+done.LogID+"/undo", nil); code != http.StatusNoContent {
		t.Errorf("admin undoes a role: %d", code)
	}

	// Items by link; unpublishing, and an undo refused after a later change.
	var items struct {
		Items []struct{ Kind, ID, Owner, Visibility string } `json:"items"`
	}
	_, body = m.do("GET", "/admin-api/v1/admin/items?q=https://alvyo.tellbow.ch/routes/"+route.ID, nil)
	_ = json.Unmarshal(body, &items)
	if len(items.Items) != 1 || items.Items[0].Owner != "troll" || items.Items[0].Visibility != "public" {
		t.Fatalf("items: %s", body)
	}
	_, body = m.do("POST", "/admin-api/v1/admin/items/route/"+route.ID+"/unpublish", nil)
	var unpublished struct {
		LogID string `json:"log_id"`
	}
	_ = json.Unmarshal(body, &unpublished)
	if visibility() != "private" {
		t.Fatalf("unpublish: %s", body)
	}
	if _, err := s.db.Exec(ctx, `UPDATE routes SET visibility = 'public' WHERE id = $1`, route.ID); err != nil {
		t.Fatal(err)
	}
	_, body = m.do("POST", "/admin-api/v1/admin/items/route/"+route.ID+"/unpublish", nil)
	_ = json.Unmarshal(body, &done)
	if code, _ := m.do("POST", "/admin-api/v1/admin/log/"+unpublished.LogID+"/undo", nil); code != http.StatusConflict {
		t.Errorf("undo before a later change: %d, want 409", code)
	}

	// A new confirmation e-mail only for an address not confirmed.
	if code, _ := m.do("POST", "/admin-api/v1/admin/users/"+trollID+"/verification", nil); code != http.StatusConflict {
		t.Errorf("verification when confirmed: %d, want 409", code)
	}
	if _, err := s.db.Exec(ctx, `UPDATE users SET email_verified_at = NULL WHERE username = 'troll'`); err != nil {
		t.Fatal(err)
	}
	sent := len(s.mail.Sent())
	if code, body := m.do("POST", "/admin-api/v1/admin/users/"+trollID+"/verification", nil); code != http.StatusOK || len(s.mail.Sent()) != sent+1 {
		t.Errorf("verification: %d %s", code, body)
	}

	// «Verlauf»: newest first, by area.
	var log struct {
		Entries []struct {
			Title    string
			Undoable bool
			UndoneAt *string `json:"undone_at"`
		} `json:"entries"`
	}
	_, body = m.do("GET", "/admin-api/v1/admin/log?area=nutzer", nil)
	_ = json.Unmarshal(body, &log)
	var titles []string
	for _, e := range log.Entries {
		titles = append(titles, e.Title)
	}
	if got := strings.Join(titles, " | "); got != "Bestätigungs-E-Mail an @troll | @troll: Rolle user → moderator | @troll gesperrt" {
		t.Errorf("log: %s", got)
	}
	if len(log.Entries) == 3 && (log.Entries[2].UndoneAt == nil || log.Entries[2].Undoable) {
		t.Errorf("the undone ban: %s", body)
	}
}
