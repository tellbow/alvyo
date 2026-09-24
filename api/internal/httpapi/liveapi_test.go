package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/tellbow/odysgeh/api/internal/live"
)

func TestLiveAPI(t *testing.T) {
	s := newTestServerWith(t, func(d *Deps) { d.Live = &live.Store{DB: d.DB, Mail: d.Auth.Mail, PublicURL: origin} })
	hiker, other, anon := s.client(t), s.client(t), s.client(t)
	hiker.do("POST", "/api/v1/auth/signup", signupBody("anna@example.ch", "anna"))
	other.do("POST", "/api/v1/auth/signup", signupBody("otto@example.ch", "otto"))

	code, raw := hiker.do("POST", "/api/v1/me/contacts", map[string]any{"name": "Bea", "email": "bea@example.ch"})
	if code != http.StatusCreated {
		t.Fatalf("add contact: %d %s", code, raw)
	}
	var bea live.Contact
	_ = json.Unmarshal(raw, &bea)
	if code, _ := hiker.do("POST", "/api/v1/me/contacts", map[string]any{"name": "Bea", "email": "bea@example.ch"}); code != http.StatusConflict {
		t.Errorf("twice: %d", code)
	}
	if _, raw := other.do("GET", "/api/v1/me/contacts", nil); strings.Contains(string(raw), "bea@") {
		t.Errorf("someone else's contacts: %s", raw)
	}

	_, raw = hiker.do("POST", "/api/v1/routes", newRouteBody("Gratweg", "private"))
	var route savedRoute
	_ = json.Unmarshal(raw, &route)
	start := map[string]any{
		"title": "Gratweg", "route_id": route.ID, "contact_ids": []string{bea.ID},
		"expected_end": time.Now().Add(5 * time.Hour).Format(time.RFC3339),
	}
	if code, _ := hiker.do("POST", "/api/v1/live", start); code != http.StatusForbidden {
		t.Errorf("unverified address: %d", code)
	}
	if _, err := s.db.Exec(context.Background(), `UPDATE users SET email_verified_at = now()`); err != nil {
		t.Fatal(err)
	}
	before := len(s.mail.Sent())
	code, raw = hiker.do("POST", "/api/v1/live", start)
	if code != http.StatusCreated {
		t.Fatalf("start: %d %s", code, raw)
	}
	var sh live.Share
	_ = json.Unmarshal(raw, &sh)
	if sent := s.mail.Sent()[before:]; len(sent) != 1 || sent[0].To != "bea@example.ch" || !strings.Contains(sent[0].Text, "/live/"+sh.Token) {
		t.Errorf("start mail: %+v", sent)
	}
	// Another user's route is not shown to one's contacts.
	_, raw = other.do("POST", "/api/v1/routes", newRouteBody("Geheim", "private"))
	var secret savedRoute
	_ = json.Unmarshal(raw, &secret)
	start["route_id"] = secret.ID
	if code, _ := hiker.do("POST", "/api/v1/live", start); code != http.StatusNotFound {
		t.Errorf("someone else's route: %d", code)
	}

	pos := map[string]any{"points": []map[string]any{{"lon": 8.001, "lat": 46.5, "t": time.Now().Format(time.RFC3339)}}}
	if code, _ := other.do("POST", "/api/v1/live/"+sh.ID+"/positions", pos); code != http.StatusNotFound {
		t.Errorf("someone else's positions: %d", code)
	}
	if code, raw := hiker.do("POST", "/api/v1/live/"+sh.ID+"/positions", pos); code != http.StatusNoContent {
		t.Fatalf("positions: %d %s", code, raw)
	}

	// The link, without logging in: the hike, nothing else of the hiker.
	code, raw = anon.do("GET", "/api/v1/live/view/"+sh.Token, nil)
	var v live.View
	_ = json.Unmarshal(raw, &v)
	if code != http.StatusOK || v.Title != "Gratweg" || v.Last == nil || v.Last.Lon != 8.001 || len(v.Route) < 2 {
		t.Fatalf("view: %d %s", code, raw)
	}
	if strings.Contains(string(raw), "anna@example.ch") || strings.Contains(string(raw), "bea@") {
		t.Errorf("addresses on the page: %s", raw)
	}
	if code, _ := anon.do("GET", "/api/v1/live/view/nope", nil); code != http.StatusNotFound {
		t.Errorf("bad token: %d", code)
	}

	if code, _ := hiker.do("PATCH", "/api/v1/live/"+sh.ID, map[string]any{"expected_end": time.Now().Add(-time.Hour).Format(time.RFC3339)}); code != http.StatusUnprocessableEntity {
		t.Errorf("later into the past: %d", code)
	}
	if code, _ := hiker.do("POST", "/api/v1/live/"+sh.ID+"/end", nil); code != http.StatusNoContent {
		t.Errorf("end: %d", code)
	}
	if code, _ := hiker.do("POST", "/api/v1/live/"+sh.ID+"/positions", pos); code != http.StatusConflict {
		t.Errorf("positions after the end: %d", code)
	}
	if _, raw := anon.do("GET", "/api/v1/live/view/"+sh.Token, nil); !strings.Contains(string(raw), `"ended_at":"`) {
		t.Errorf("ended view: %s", raw)
	}
}
