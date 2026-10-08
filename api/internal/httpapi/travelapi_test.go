package httpapi

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"
)

func TestTravel(t *testing.T) {
	s := newTestServer(t, Limits{})
	anna, bea := s.client(t), s.client(t)
	s.signup(anna, "anna@example.ch", "anna")
	s.signup(bea, "bea@example.ch", "bea")
	if _, err := s.db.Exec(t.Context(), `UPDATE users SET email_verified_at = now()`); err != nil {
		t.Fatal(err)
	}
	home := func(c *client, name, address string) string {
		t.Helper()
		code, body := c.do("POST", "/api/v1/me/homes", map[string]any{"name": name, "address": address, "lon": 7.6197, "lat": 46.764})
		var h struct {
			ID string `json:"id"`
		}
		if err := json.Unmarshal(body, &h); code != http.StatusCreated || err != nil {
			t.Fatalf("add home: %d %s", code, body)
		}
		return h.ID
	}
	thun := home(anna, "Zuhause", "Länggasse 13B, 3600 Thun")
	for range 4 {
		home(anna, "Büro", "Bahnhofplatz 1, 3011 Bern")
	}
	if code, _ := anna.do("POST", "/api/v1/me/homes", map[string]any{"name": "zu viel", "address": "x", "lon": 7.0, "lat": 46.0}); code != http.StatusUnprocessableEntity {
		t.Errorf("sixth home: %d", code)
	}
	_, body := anna.do("GET", "/api/v1/me/homes", nil)
	if !strings.Contains(string(body), "Länggasse 13B") {
		t.Errorf("homes: %s", body)
	}
	if _, body := bea.do("GET", "/api/v1/me/homes", nil); strings.Contains(string(body), "Länggasse") {
		t.Errorf("bea sees anna's homes: %s", body)
	}

	code, body := anna.do("POST", "/api/v1/journeys", map[string]any{"title": "Spiez – Zermatt", "visibility": "private"})
	if code != http.StatusCreated {
		t.Fatalf("create: %d %s", code, body)
	}
	j := decodeJourney(t, body)
	at := "/api/v1/journeys/" + j.ID + "/travel"
	way := map[string]any{
		"to":   map[string]any{"home_id": thun, "time": "06:00", "arrive": false},
		"back": map[string]any{"home_id": thun, "time": "20:00", "arrive": true},
	}
	if code, body := anna.do("PUT", at, way); code != http.StatusOK || !strings.Contains(string(body), `"time":"06:00"`) {
		t.Fatalf("set travel: %d %s", code, body)
	}
	for _, bad := range []map[string]any{
		{"to": map[string]any{"home_id": "Thun", "time": "06:00", "arrive": false}},
		{"to": map[string]any{"home_id": thun, "time": "6 Uhr", "arrive": false}},
		{"to": map[string]any{"time": "06:00", "arrive": false}},
		{"to": map[string]any{"home_id": thun, "place": map[string]any{"name": "Bern", "lon": 7.44, "lat": 46.95}, "time": "06:00", "arrive": false}},
		{"to": map[string]any{"place": map[string]any{"name": " ", "lon": 7.44, "lat": 46.95}, "time": "06:00", "arrive": false}},
	} {
		if code, body := anna.do("PUT", at, bad); code != http.StatusUnprocessableEntity {
			t.Errorf("bad travel %v: %d %s", bad, code, body)
		}
	}

	// Not bea's journey: as if it did not exist.
	if code, _ := bea.do("GET", at, nil); code != http.StatusNotFound {
		t.Errorf("bea, private journey: %d", code)
	}
	// Shared by link: bea chooses her own way; anna's stays hers.
	etag := fmt.Sprintf(`"%d"`, j.Version)
	code, body = anna.do("PATCH", "/api/v1/journeys/"+j.ID, map[string]any{"visibility": "unlisted"}, "If-Match", etag)
	var shared struct {
		Token string `json:"share_token"`
	}
	if err := json.Unmarshal(body, &shared); code != http.StatusOK || err != nil || shared.Token == "" {
		t.Fatalf("unlisted: %d %s", code, body)
	}
	byLink := at + "?t=" + shared.Token
	if code, body := bea.do("GET", byLink, nil); code != http.StatusOK || strings.Contains(string(body), `"to"`) {
		t.Errorf("bea's travel: %d %s", code, body)
	}
	if code, _ := bea.do("PUT", byLink, map[string]any{"to": map[string]any{"home_id": thun, "time": "07:00", "arrive": false}}); code != http.StatusNotFound {
		t.Errorf("bea with anna's home: %d", code)
	}
	beaHome := home(bea, "Zuhause", "Rue du Lac 1, 1003 Lausanne")
	if code, _ := bea.do("PUT", byLink, map[string]any{"to": map[string]any{"home_id": beaHome, "time": "07:30", "arrive": true}}); code != http.StatusOK {
		t.Errorf("bea's own: %d", code)
	}
	if _, body := anna.do("GET", at, nil); !strings.Contains(string(body), `"time":"06:00"`) || strings.Contains(string(body), "07:30") {
		t.Errorf("anna's travel: %s", body)
	}

	// Nobody sees a home in the journey or its GPX.
	for _, path := range []string{"/api/v1/journeys/" + j.ID + "?t=" + shared.Token, "/api/v1/journeys/" + j.ID + "/gpx?t=" + shared.Token} {
		_, body := bea.do("GET", path, nil)
		if strings.Contains(string(body), "Länggasse") || strings.Contains(string(body), "7.6197") {
			t.Errorf("%s shows a home: %s", path, body)
		}
	}

	// A home deleted: the travel from it goes.
	if code, _ := anna.do("DELETE", "/api/v1/me/homes/"+thun, nil); code != http.StatusNoContent {
		t.Errorf("delete home: %d", code)
	}
	if _, body := anna.do("GET", at, nil); strings.Contains(string(body), `"to"`) {
		t.Errorf("after deleting the home: %s", body)
	}

	// A route: from anywhere, to its start and back from its end.
	_, body = anna.do("POST", "/api/v1/routes", newRouteBody("Gantrisch", "private"))
	var r savedRoute
	_ = json.Unmarshal(body, &r)
	rat := "/api/v1/routes/" + r.ID + "/travel"
	bern := map[string]any{"name": "Bern, Bahnhof", "lon": 7.4391, "lat": 46.949}
	if code, body := anna.do("PUT", rat, map[string]any{"to": map[string]any{"place": bern, "time": "07:00", "arrive": false}}); code != http.StatusOK ||
		!strings.Contains(string(body), `"name":"Bern, Bahnhof"`) {
		t.Errorf("route travel: %d %s", code, body)
	}
	if _, body := anna.do("GET", rat, nil); !strings.Contains(string(body), "Bern, Bahnhof") {
		t.Errorf("route travel read: %s", body)
	}
	if code, _ := bea.do("GET", rat, nil); code != http.StatusNotFound {
		t.Errorf("bea, private route: %d", code)
	}
	if code, _ := s.client(t).do("GET", rat, nil); code != http.StatusUnauthorized {
		t.Errorf("signed out: %d", code)
	}
}
