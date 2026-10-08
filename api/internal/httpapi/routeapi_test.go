package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"image"
	"image/jpeg"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/tellbow/alvyo/api/internal/og"
)

func routeLeg(lon0 float64) map[string]any {
	coords := [][3]float64{}
	for i := 0; i <= 4; i++ {
		coords = append(coords, [3]float64{lon0 + float64(i)*0.0005, 46.5, 1000 + float64(i)*5})
	}
	run := func(v string) []map[string]any { return []map[string]any{{"from": 0, "to": 4, "value": v}} }
	return map[string]any{
		"coordinates": coords, "distance_m": 0, "ascent_m": 0, "descent_m": 0, "ele_min_m": 0, "ele_max_m": 0,
		"duration_s": 0, "duration_reverse_s": 0,
		"sac":      map[string]any{"grade": 0, "max": 3, "breakdown": map[string]any{}, "unofficial_m": 0},
		"surfaces": map[string]any{}, "way_types": map[string]any{}, "trails": map[string]any{},
		"details": map[string]any{"sac": run("T2"), "surface": run("gravel"), "way_type": run("path"), "trail": run("Wanderweg")},
		"snap":    map[string]any{"from_m": 0, "to_m": 0}, "warnings": []string{},
	}
}

func newRouteBody(title, visibility string) map[string]any {
	return map[string]any{
		"title": title, "visibility": visibility, "profile": "hike",
		"anchors": []map[string]any{{"lon": 8.0, "lat": 46.5}, {"lon": 8.002, "lat": 46.5}, {"lon": 8.004, "lat": 46.5}},
		"legs":    []map[string]any{routeLeg(8.0), routeLeg(8.002)},
	}
}

type savedRoute struct {
	ID      string `json:"id"`
	Title   string `json:"title"`
	Version int    `json:"version"`
	CanEdit bool   `json:"can_edit"`
	Totals  struct {
		DistanceM float64 `json:"distance_m"`
		AscentM   float64 `json:"ascent_m"`
		SACGrade  int     `json:"sac_grade"`
	} `json:"totals"`
	Legs []json.RawMessage `json:"legs"`
}

func TestRouteLifecycle(t *testing.T) {
	s := newTestServer(t, Limits{})
	owner := s.client(t)
	s.signup(owner, "owner@example.ch", "owner")
	other := s.client(t)
	s.signup(other, "other@example.ch", "other")
	anon := s.client(t)

	code, body := owner.do("POST", "/api/v1/routes", newRouteBody("Gratweg", "private"))
	if code != http.StatusCreated {
		t.Fatalf("create: %d %s", code, body)
	}
	var r savedRoute
	_ = json.Unmarshal(body, &r)
	if r.Version != 1 || !r.CanEdit || len(r.Legs) != 2 || r.Totals.AscentM != 40 || r.Totals.SACGrade != 2 {
		t.Errorf("created: %+v", r)
	}
	path := "/api/v1/routes/" + r.ID

	// A leg dragged onto another path keeps the point it was dragged to.
	body2 := newRouteBody("Umweg", "private")
	body2["anchors"].([]map[string]any)[1]["through"] = map[string]any{"lon": 8.001, "lat": 46.501}
	_, body = owner.do("POST", "/api/v1/routes", body2)
	var shaped struct {
		Anchors []struct {
			Through *struct{ Lon, Lat float64 } `json:"through"`
		} `json:"anchors"`
	}
	_ = json.Unmarshal(body, &shaped)
	if len(shaped.Anchors) != 3 || shaped.Anchors[0].Through != nil || shaped.Anchors[1].Through == nil ||
		shaped.Anchors[1].Through.Lon != 8.001 {
		t.Errorf("through not kept: %s", body)
	}

	// Private: only the owner sees it.
	if code, _ := other.do("GET", path, nil); code != http.StatusNotFound {
		t.Errorf("other sees private route: %d", code)
	}
	if code, _ := anon.do("GET", path, nil); code != http.StatusNotFound {
		t.Errorf("anonymous sees private route: %d", code)
	}
	code, body = owner.do("GET", "/api/v1/routes", nil)
	if code != http.StatusOK || !json.Valid(body) {
		t.Fatalf("list: %d %s", code, body)
	}

	// Publishing needs a verified e-mail address.
	if code, _ := owner.do("PATCH", path, map[string]any{"visibility": "public"}, "If-Match", `"1"`); code != http.StatusForbidden {
		t.Errorf("publish unverified: %d", code)
	}
	if _, err := s.db.Exec(context.Background(), `UPDATE users SET email_verified_at = now() WHERE username = 'owner'`); err != nil {
		t.Fatal(err)
	}
	code, body = owner.do("PATCH", path, map[string]any{"visibility": "public", "title": "Gratweg Nord"}, "If-Match", `"1"`)
	if code != http.StatusOK {
		t.Fatalf("publish: %d %s", code, body)
	}

	// Public: visible to all, editable by nobody else.
	code, body = anon.do("GET", path, nil)
	_ = json.Unmarshal(body, &r)
	if code != http.StatusOK || r.CanEdit || r.Title != "Gratweg Nord" || r.Version != 2 {
		t.Errorf("anonymous view of public route: %d %+v", code, r)
	}
	if code, _ := other.do("PATCH", path, map[string]any{"title": "mine now"}, "If-Match", `"2"`); code != http.StatusForbidden {
		t.Errorf("other edits: %d", code)
	}

	// Stale version → 412; content change bumps the version.
	if code, _ := owner.do("PATCH", path, map[string]any{"title": "stale"}, "If-Match", `"1"`); code != http.StatusPreconditionFailed {
		t.Errorf("stale edit: %d", code)
	}
	longer := newRouteBody("", "")
	longer["anchors"] = append(longer["anchors"].([]map[string]any), map[string]any{"lon": 8.006, "lat": 46.5})
	longer["legs"] = append(longer["legs"].([]map[string]any), routeLeg(8.004))
	delete(longer, "title")
	delete(longer, "visibility")
	code, body = owner.do("PATCH", path, longer, "If-Match", `"2"`)
	_ = json.Unmarshal(body, &r)
	if code != http.StatusOK || len(r.Legs) != 3 || r.Version != 3 {
		t.Fatalf("content edit: %d %s", code, body)
	}
	half := map[string]any{"anchors": longer["anchors"]}
	if code, _ := owner.do("PATCH", path, half, "If-Match", `"3"`); code != http.StatusUnprocessableEntity {
		t.Errorf("anchors without legs: %d", code)
	}

	code, gpxBody := anon.do("GET", path+"/gpx", nil)
	if code != http.StatusOK || !strings.Contains(string(gpxBody), "<trkpt") || strings.Count(string(gpxBody), "<trkpt") != 13 {
		t.Errorf("gpx: %d, %d points", code, strings.Count(string(gpxBody), "<trkpt"))
	}

	if code, _ := other.do("DELETE", path, nil); code != http.StatusForbidden {
		t.Errorf("other deletes: %d", code)
	}
	if code, _ := owner.do("DELETE", path, nil); code != http.StatusNoContent {
		t.Errorf("delete: %d", code)
	}
	if code, _ := owner.do("GET", path, nil); code != http.StatusNotFound {
		t.Errorf("after delete: %d", code)
	}
}

func TestCreateRouteValidation(t *testing.T) {
	s := newTestServer(t, Limits{})
	c := s.client(t)
	s.signup(c, "val@example.ch", "validator")
	body := newRouteBody("Too far apart", "private")
	body["legs"] = []map[string]any{routeLeg(8.0), routeLeg(8.1)} // second leg starts ~7 km away
	if code, resp := c.do("POST", "/api/v1/routes", body); code != http.StatusUnprocessableEntity {
		t.Errorf("gap: %d %s", code, resp)
	}
	if code, _ := s.client(t).do("POST", "/api/v1/routes", newRouteBody("anon", "private")); code != http.StatusUnauthorized {
		t.Errorf("anonymous create: %d", code)
	}
	if code, _ := c.do("GET", "/api/v1/routes/not-a-uuid", nil); code != http.StatusNotFound && code != http.StatusUnprocessableEntity {
		t.Errorf("bad id: %d", code)
	}
}

func TestShareLink(t *testing.T) {
	s := newTestServer(t, Limits{})
	owner := s.client(t)
	s.signup(owner, "linker@example.ch", "linker")
	anon := s.client(t)

	if code, _ := owner.do("POST", "/api/v1/routes", newRouteBody("Too early", "unlisted")); code != http.StatusForbidden {
		t.Errorf("unverified unlisted: %d", code)
	}
	if _, err := s.db.Exec(context.Background(), `UPDATE users SET email_verified_at = now()`); err != nil {
		t.Fatal(err)
	}
	code, body := owner.do("POST", "/api/v1/routes", newRouteBody("Mit Link", "unlisted"))
	var r struct {
		savedRoute
		ShareToken string `json:"share_token"`
	}
	_ = json.Unmarshal(body, &r)
	if code != http.StatusCreated || len(r.ShareToken) != 22 {
		t.Fatalf("create unlisted: %d %s", code, body)
	}
	path := "/api/v1/routes/" + r.ID

	if code, _ := anon.do("GET", path, nil); code != http.StatusNotFound {
		t.Errorf("no token: %d", code)
	}
	if code, _ := anon.do("GET", path+"?t=wrong-token-wrong-token", nil); code != http.StatusNotFound {
		t.Errorf("wrong token: %d", code)
	}
	code, body = anon.do("GET", path+"?t="+r.ShareToken, nil)
	if code != http.StatusOK || strings.Contains(string(body), "share_token") {
		t.Errorf("with token: %d, token leaked: %v", code, strings.Contains(string(body), "share_token"))
	}
	if code, _ := anon.do("GET", path+"/gpx?t="+r.ShareToken, nil); code != http.StatusOK {
		t.Errorf("gpx with token: %d", code)
	}

	code, body = owner.do("POST", path+"/link/rotate", nil)
	var rot struct {
		ShareToken string `json:"share_token"`
	}
	_ = json.Unmarshal(body, &rot)
	if code != http.StatusOK || rot.ShareToken == r.ShareToken {
		t.Fatalf("rotate: %d %s", code, body)
	}
	if code, _ := anon.do("GET", path+"?t="+r.ShareToken, nil); code != http.StatusNotFound {
		t.Errorf("old token after rotate: %d", code)
	}
	if code, _ := anon.do("POST", path+"/link/rotate", nil); code != http.StatusNotFound {
		t.Errorf("anonymous rotate: %d", code)
	}

	// Private again: the link stops working.
	owner.do("PATCH", path, map[string]any{"visibility": "private"}, "If-Match", `"1"`)
	if code, _ := anon.do("GET", path+"?t="+rot.ShareToken, nil); code != http.StatusNotFound {
		t.Errorf("token on private route: %d", code)
	}
}

func TestEditorKeepsVisibility(t *testing.T) {
	// An editor who has not confirmed the address yet saves a title together
	// with the unchanged visibility, as the web app sends it.
	s := newTestServer(t, Limits{})
	owner, editor := s.client(t), s.client(t)
	s.signup(owner, "owner@example.ch", "owner")
	s.signup(editor, "editor@example.ch", "editor")
	if _, err := s.db.Exec(context.Background(), `UPDATE users SET email_verified_at = now() WHERE username = 'owner'`); err != nil {
		t.Fatal(err)
	}
	for _, kind := range []string{"routes", "journeys"} {
		body := newRouteBody("Gratweg", "public")
		if kind == "journeys" {
			body = map[string]any{"title": "Via Alpina", "visibility": "public"}
		}
		code, created := owner.do("POST", "/api/v1/"+kind, body)
		var item struct {
			ID      string `json:"id"`
			Version int    `json:"version"`
		}
		if err := json.Unmarshal(created, &item); code != http.StatusCreated || err != nil {
			t.Fatalf("%s: %d %s", kind, code, created)
		}
		base := "/api/v1/" + kind + "/" + item.ID
		owner.do("POST", base+"/grants", map[string]any{"username": "editor", "role": "editor"})
		code, resp := editor.do("PATCH", base, map[string]any{"title": "Neu", "visibility": "public"}, "If-Match", `"`+strconv.Itoa(item.Version)+`"`)
		if code != http.StatusOK {
			t.Errorf("%s: %d %s", kind, code, resp)
		}
	}
}

// imageServer is a test server that renders preview images on blank tiles,
// with a verified user «owner» logged in.
func imageServer(t *testing.T) (*testServer, *client, func(c *client, path string) (int, string, string)) {
	tile := image.NewRGBA(image.Rect(0, 0, 256, 256))
	var buf bytes.Buffer
	_ = jpeg.Encode(&buf, tile, nil)
	tiles := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "image/jpeg")
		_, _ = w.Write(buf.Bytes())
	}))
	t.Cleanup(tiles.Close)
	s := newTestServerWith(t, func(d *Deps) { d.Images = &og.Renderer{TilesURL: tiles.URL, CacheDir: t.TempDir()} })
	owner := s.client(t)
	s.signup(owner, "owner@example.ch", "owner")
	if _, err := s.db.Exec(context.Background(), `UPDATE users SET email_verified_at = now()`); err != nil {
		t.Fatal(err)
	}
	image := func(c *client, path string) (int, string, string) {
		t.Helper()
		resp, err := c.http.Get(s.URL + "/api/v1/" + path + "/og.png")
		if err != nil {
			t.Fatal(err)
		}
		defer func() { _ = resp.Body.Close() }()
		return resp.StatusCode, resp.Header.Get("Content-Type"), resp.Header.Get("Cache-Control")
	}
	return s, owner, image
}

func TestRouteImage(t *testing.T) {
	s, owner, image := imageServer(t)
	for _, tc := range []struct{ visibility, cache string }{{"public", "public"}, {"private", "private"}} {
		_, body := owner.do("POST", "/api/v1/routes", newRouteBody("Gratweg", tc.visibility))
		var r savedRoute
		_ = json.Unmarshal(body, &r)
		code, ctype, cache := image(owner, "routes/"+r.ID)
		if code != http.StatusOK || ctype != "image/png" || !strings.HasPrefix(cache, tc.cache+",") {
			t.Errorf("%s route: %d %s %q", tc.visibility, code, ctype, cache)
		}
		if tc.visibility == "private" {
			if code, _, _ := image(s.client(t), "routes/"+r.ID); code != http.StatusNotFound {
				t.Errorf("private route to someone else: %d", code)
			}
		}
	}
}

func TestJourneyAndCollectionImages(t *testing.T) {
	s, owner, image := imageServer(t)
	anon := s.client(t)

	_, body := owner.do("POST", "/api/v1/journeys", map[string]any{"title": "Reise", "visibility": "public"})
	var j journeyResp
	_ = json.Unmarshal(body, &j)
	// No stage route yet: nothing to show.
	if code, _, _ := image(anon, "journeys/"+j.ID); code != http.StatusNotFound {
		t.Errorf("journey without routes: %d", code)
	}
	_, body = owner.do("POST", "/api/v1/journeys/"+j.ID+"/stages", map[string]any{})
	j = decodeJourney(t, body)
	stage := lineRoute("", "", 8.02, 46.6, "T2")
	delete(stage, "title")
	delete(stage, "visibility")
	if code, body := owner.do("POST", "/api/v1/journeys/"+j.ID+"/stages/"+j.StageList[0].ID+"/route", stage); code != http.StatusOK {
		t.Fatalf("stage route: %d %s", code, body)
	}
	if code, ctype, cache := image(anon, "journeys/"+j.ID); code != http.StatusOK || ctype != "image/png" || !strings.HasPrefix(cache, "public,") {
		t.Errorf("public journey: %d %s %q", code, ctype, cache)
	}

	// A collection shows the items the caller may see, and is never cached
	// for others.
	_, body = owner.do("POST", "/api/v1/collections", map[string]any{"title": "Gipfel", "visibility": "public"})
	var c struct{ ID string }
	_ = json.Unmarshal(body, &c)
	if code, _, _ := image(anon, "collections/"+c.ID); code != http.StatusNotFound {
		t.Errorf("empty collection: %d", code)
	}
	_, body = owner.do("POST", "/api/v1/routes", newRouteBody("Geheim", "private"))
	var r savedRoute
	_ = json.Unmarshal(body, &r)
	owner.do("POST", "/api/v1/collections/"+c.ID+"/items", map[string]any{"route_id": r.ID})
	if code, _, cache := image(owner, "collections/"+c.ID); code != http.StatusOK || !strings.HasPrefix(cache, "private,") {
		t.Errorf("collection to its owner: %d %q", code, cache)
	}
	if code, _, cache := image(anon, "collections/"+c.ID); code != http.StatusOK || !strings.HasPrefix(cache, "private,") {
		t.Errorf("collection sharing its owner's private route: %d %q", code, cache)
	}
}
