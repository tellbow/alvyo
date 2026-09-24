package httpapi

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tellbow/odysgeh/api/internal/imports"
	"github.com/tellbow/odysgeh/api/internal/routing"
)

// upload posts a multipart form with a file.
func (c *client) upload(path, filename, content string, fields ...string) (int, []byte) {
	c.t.Helper()
	var b bytes.Buffer
	w := multipart.NewWriter(&b)
	for i := 0; i+1 < len(fields); i += 2 {
		_ = w.WriteField(fields[i], fields[i+1])
	}
	f, _ := w.CreateFormFile("file", filename)
	_, _ = f.Write([]byte(content))
	_ = w.Close()
	req, _ := http.NewRequest("POST", c.base+path, &b)
	req.Header.Set("Content-Type", w.FormDataContentType())
	req.Header.Set("Origin", origin)
	resp, err := c.http.Do(req)
	if err != nil {
		c.t.Fatal(err)
	}
	defer func() { _ = resp.Body.Close() }()
	out, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, out
}

// line is a GPX track east from lon at 46.66° N (Faulhorn area when lon ≈ 8).
func line(name string, lon, lat float64, n int) string {
	var b strings.Builder
	fmt.Fprintf(&b, "<trk><name>%s</name><trkseg>", name)
	for i := range n {
		fmt.Fprintf(&b, `<trkpt lat="%f" lon="%f"/>`, lat, lon+float64(i)*0.001)
	}
	b.WriteString("</trkseg></trk>")
	return b.String()
}

func gpxDoc(tracks ...string) string {
	return `<?xml version="1.0"?><gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">` +
		strings.Join(tracks, "") + `</gpx>`
}

func newImportServer(t *testing.T, komootURL string) *testServer {
	return newTestServerWith(t, func(d *Deps) {
		router := &routing.Router{Elevation: flatSampler{}, Trails: &routing.TrailMatcher{DB: d.DB}}
		d.Importer = &imports.Importer{Router: router, Routes: d.Routes, Journeys: d.Journeys}
		d.Komoot = &imports.Komoot{API: komootURL}
	})
}

type importResp struct {
	Routes []struct {
		ID    string `json:"id"`
		Title string `json:"title"`
		Ref   string `json:"ref"`
	} `json:"routes"`
	JourneyID string            `json:"journey_id"`
	Skipped   []imports.Skipped `json:"skipped"`
}

// imported decodes an import response.
func (c *client) imported(code int, body []byte) importResp {
	c.t.Helper()
	if code != http.StatusOK {
		c.t.Fatalf("import: %d %s", code, body)
	}
	var r importResp
	if err := json.Unmarshal(body, &r); err != nil {
		c.t.Fatal(err)
	}
	return r
}

func TestImportFile(t *testing.T) {
	s := newImportServer(t, "http://komoot.invalid")
	c := s.client(t)
	file := gpxDoc(line("Tag 1", 8.00, 46.66, 30), line("Tag 2", 8.03, 46.66, 30), line("Mailand", 9.19, 45.46, 5))

	if code, _ := c.upload("/api/v1/imports/preview", "tour.gpx", file); code != http.StatusUnauthorized {
		t.Errorf("anonymous preview: %d, want 401", code)
	}
	c.do("POST", "/api/v1/auth/signup", signupBody("importer@example.ch", "importer"))

	code, body := c.upload("/api/v1/imports/preview", "tour.gpx", file)
	var preview struct {
		Format string         `json:"format"`
		Tracks []trackSummary `json:"tracks"`
	}
	_ = json.Unmarshal(body, &preview)
	if code != http.StatusOK || preview.Format != "gpx" || len(preview.Tracks) != 3 ||
		preview.Tracks[0].Name != "Tag 1" || !preview.Tracks[0].Inside || preview.Tracks[2].Inside ||
		preview.Tracks[0].DistanceM < 2100 || preview.Tracks[0].DistanceM > 2300 {
		t.Fatalf("preview: %d %s", code, body)
	}
	if code, body := c.upload("/api/v1/imports/preview", "notes.gpx", "hello"); code != http.StatusUnprocessableEntity {
		t.Errorf("not a track file: %d %s", code, body)
	}
	if code, body := c.upload("/api/v1/imports/preview", "empty.gpx", gpxDoc()); code != http.StatusUnprocessableEntity {
		t.Errorf("no track: %d %s", code, body)
	}

	// One route per track; the one in Milan is skipped.
	r := c.imported(c.upload("/api/v1/imports", "tour.gpx", file, "mode", "routes"))
	if len(r.Routes) != 2 || r.Routes[0].Title != "Tag 1" || len(r.Skipped) != 1 ||
		r.Skipped[0] != (imports.Skipped{Name: "Mailand", Reason: "outside"}) {
		t.Fatalf("routes: %+v", r)
	}
	code, body = c.do("GET", "/api/v1/routes/"+r.Routes[0].ID, nil)
	var route savedRoute
	_ = json.Unmarshal(body, &route)
	if code != http.StatusOK || route.Totals.DistanceM < 2000 || len(route.Legs) != 1 {
		t.Fatalf("imported route: %d %s", code, body)
	}

	// All inside tracks as one route, titled.
	r = c.imported(c.upload("/api/v1/imports", "tour.gpx", gpxDoc(line("Tag 1", 8.00, 46.66, 30), line("Tag 2", 8.03, 46.66, 30)),
		"mode", "route", "title", "Zwei Tage"))
	if len(r.Routes) != 1 || r.Routes[0].Title != "Zwei Tage" || len(r.Skipped) != 0 {
		t.Fatalf("joined: %+v", r)
	}
	_, body = c.do("GET", "/api/v1/routes/"+r.Routes[0].ID, nil)
	_ = json.Unmarshal(body, &route)
	if route.Totals.DistanceM < 4300 || len(route.Legs) != 2 {
		t.Errorf("joined route: %.0f m, %d legs", route.Totals.DistanceM, len(route.Legs))
	}

	// A journey with a stage per track; the Milan stage has no route.
	r = c.imported(c.upload("/api/v1/imports", "tour.gpx", file, "mode", "journey", "title", "Durchquerung"))
	if r.JourneyID == "" || len(r.Skipped) != 1 {
		t.Fatalf("journey: %+v", r)
	}
	code, body = c.do("GET", "/api/v1/journeys/"+r.JourneyID, nil)
	j := decodeJourney(t, body)
	if code != http.StatusOK || len(j.StageList) != 3 || j.StageList[1].Title != "Tag 2" ||
		j.StageList[1].Route == nil || j.StageList[2].Route != nil {
		t.Fatalf("imported journey: %d %s", code, body)
	}

	// Only the importer sees them.
	other := s.client(t)
	other.do("POST", "/api/v1/auth/signup", signupBody("other@example.ch", "other"))
	if code, _ := other.do("GET", "/api/v1/journeys/"+r.JourneyID, nil); code != http.StatusNotFound {
		t.Errorf("other user sees the imported journey: %d", code)
	}
}

// fakeKomoot mimics the Komoot login, tour list and tour endpoints.
func fakeKomoot(t *testing.T) string {
	t.Helper()
	basic := func(user, secret string) string {
		return "Basic " + base64.StdEncoding.EncodeToString([]byte(user+":"+secret))
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v006/account/email/{email}/", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != basic(r.PathValue("email"), "right") {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		_, _ = w.Write([]byte(`{"username":"42","password":"api-token"}`))
	})
	mux.HandleFunc("GET /v007/users/42/tours/", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"_embedded":{"tours":[
			{"id":1,"type":"tour_recorded","name":"Faulhorn","date":"2026-08-01T07:00:00.000Z","sport":"hike","distance":2200},
			{"id":2,"type":"tour_planned","name":"Navigli","date":"2026-07-01T07:00:00.000Z","sport":"hike","distance":400}
		]},"page":{"totalPages":1}}`))
	})
	tour := func(name string, lon, lat float64) string {
		var items []string
		for i := range 30 {
			items = append(items, fmt.Sprintf(`{"lat":%f,"lng":%f}`, lat, lon+float64(i)*0.001))
		}
		return `{"name":"` + name + `","_embedded":{"coordinates":{"items":[` + strings.Join(items, ",") + `]}}}`
	}
	mux.HandleFunc("GET /v007/tours/{id}", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != basic("42", "api-token") {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		switch r.PathValue("id") {
		case "1":
			_, _ = w.Write([]byte(tour("Faulhorn", 8.0, 46.66)))
		case "2":
			_, _ = w.Write([]byte(tour("Navigli", 9.17, 45.45)))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return srv.URL
}

func TestImportKomoot(t *testing.T) {
	s := newImportServer(t, fakeKomoot(t))
	c := s.client(t)
	c.do("POST", "/api/v1/auth/signup", signupBody("komoot@example.ch", "komooter"))

	if code, body := c.do("POST", "/api/v1/imports/komoot/login", map[string]any{"email": "k@example.ch", "password": "wrong"}); code != http.StatusUnprocessableEntity {
		t.Errorf("wrong password: %d %s", code, body)
	}
	code, body := c.do("POST", "/api/v1/imports/komoot/login", map[string]any{"email": "k@example.ch", "password": "right"})
	var tours struct {
		Session string       `json:"session"`
		Tours   []komootTour `json:"tours"`
	}
	_ = json.Unmarshal(body, &tours)
	if code != http.StatusOK || tours.Session == "" || len(tours.Tours) != 2 || tours.Tours[0].Name != "Faulhorn" || tours.Tours[0].ImportedRouteID != "" {
		t.Fatalf("login: %d %s", code, body)
	}
	if strings.Contains(string(body), "api-token") {
		t.Error("the Komoot token reached the browser")
	}

	r := c.imported(c.do("POST", "/api/v1/imports/komoot", map[string]any{"session": tours.Session, "tour_ids": []int{1, 2, 3}}))
	if len(r.Routes) != 1 || r.Routes[0].Title != "Faulhorn" || r.Routes[0].Ref != "1" || len(r.Skipped) != 2 ||
		r.Skipped[0] != (imports.Skipped{Name: "Navigli", Reason: "outside"}) || r.Skipped[1].Reason != "other" {
		t.Fatalf("import: %+v", r)
	}

	// Imported tours are marked, and not imported twice.
	_, body = c.do("GET", "/api/v1/imports/komoot/tours?session="+tours.Session, nil)
	_ = json.Unmarshal(body, &tours)
	if len(tours.Tours) != 2 || tours.Tours[0].ImportedRouteID != r.Routes[0].ID {
		t.Fatalf("tours after import: %s", body)
	}
	again := c.imported(c.do("POST", "/api/v1/imports/komoot", map[string]any{"session": tours.Session, "tour_ids": []int{1}}))
	if len(again.Routes) != 0 || len(again.Skipped) != 1 || again.Skipped[0].Reason != "duplicate" {
		t.Errorf("second import: %+v", again)
	}

	// The session is bound to the user.
	other := s.client(t)
	other.do("POST", "/api/v1/auth/signup", signupBody("other@example.ch", "other"))
	if code, _ := other.do("GET", "/api/v1/imports/komoot/tours?session="+tours.Session, nil); code != http.StatusUnauthorized {
		t.Errorf("another user's session: %d, want 401", code)
	}
	if code, _ := other.do("POST", "/api/v1/imports/komoot", map[string]any{"session": tours.Session, "tour_ids": []int{1}}); code != http.StatusUnauthorized {
		t.Errorf("another user's import: %d, want 401", code)
	}
}

func TestImportIntoStage(t *testing.T) {
	s := newImportServer(t, "http://komoot.invalid")
	var stop string
	if err := s.db.QueryRow(context.Background(), `INSERT INTO places (kind, name, source, source_id, geom)
		VALUES ('pt_stop', 'Faulhorn', 'didok', '1', ST_SetSRID(ST_MakePoint(8.059, 46.66), 4326)) RETURNING id`).Scan(&stop); err != nil {
		t.Fatal(err)
	}
	owner, viewer, stranger := s.client(t), s.client(t), s.client(t)
	owner.do("POST", "/api/v1/auth/signup", signupBody("stages@example.ch", "stages"))
	viewer.do("POST", "/api/v1/auth/signup", signupBody("vie@example.ch", "vie"))
	stranger.do("POST", "/api/v1/auth/signup", signupBody("str@example.ch", "str"))
	if _, err := s.db.Exec(context.Background(), `UPDATE users SET email_verified_at = now()`); err != nil {
		t.Fatal(err)
	}

	_, body := owner.do("POST", "/api/v1/journeys", map[string]any{"title": "Zwei Tage"})
	base := "/api/v1/journeys/" + decodeJourney(t, body).ID
	owner.do("POST", base+"/stages", map[string]any{"title": "Tag 1"})
	_, body = owner.do("POST", base+"/stages", map[string]any{"title": "Tag 2"})
	st1, st2 := decodeJourney(t, body).StageList[0].ID, decodeJourney(t, body).StageList[1].ID
	if code, body := owner.do("POST", base+"/grants", map[string]any{"username": "vie", "role": "viewer"}); code != http.StatusOK {
		t.Fatalf("invite: %d %s", code, body)
	}

	type stageJourney struct {
		StageList []struct {
			Title string `json:"title"`
			Route *struct {
				ID     string `json:"id"`
				Totals struct {
					DistanceM float64 `json:"distance_m"`
				} `json:"totals"`
			} `json:"route"`
			EndPlace *struct {
				ID string `json:"id"`
			} `json:"end_place"`
			Gap *struct {
				Status string `json:"status"`
			} `json:"gap"`
		} `json:"stage_list"`
		Totals struct {
			DistanceM float64 `json:"distance_m"`
		} `json:"totals"`
	}
	imported := func(code int, body []byte) stageJourney {
		t.Helper()
		if code != http.StatusOK {
			t.Fatalf("stage import: %d %s", code, body)
		}
		var j stageJourney
		if err := json.Unmarshal(body, &j); err != nil {
			t.Fatal(err)
		}
		return j
	}

	imported(owner.upload(base+"/stages/"+st1+"/import", "tag1.gpx", gpxDoc(line("Tag 1", 8.00, 46.66, 30))))
	// Two tracks in the file are joined; stage 2 starts where stage 1 ends.
	j := imported(owner.upload(base+"/stages/"+st2+"/import", "tag2.gpx",
		gpxDoc(line("Vormittag", 8.03, 46.66, 15), line("Nachmittag", 8.045, 46.66, 15))))
	st := j.StageList[1]
	if st.Route == nil || st.Route.Totals.DistanceM < 2100 || st.Title != "Tag 2" ||
		st.Gap == nil || st.Gap.Status != "ok" || st.EndPlace == nil || st.EndPlace.ID != stop ||
		j.Totals.DistanceM < 4300 {
		t.Fatalf("stage 2: %+v, totals %+v", st, j.Totals)
	}
	routeID := st.Route.ID

	// A stage with a route keeps it unless the request replaces it.
	shorter := gpxDoc(line("Kurz", 8.03, 46.66, 10))
	if code, body := owner.upload(base+"/stages/"+st2+"/import", "kurz.gpx", shorter); code != http.StatusConflict {
		t.Errorf("import over a route: %d %s", code, body)
	}
	j = imported(owner.upload(base+"/stages/"+st2+"/import", "kurz.gpx", shorter, "replace", "true"))
	if st := j.StageList[1]; st.Route.ID != routeID || st.Route.Totals.DistanceM > 1000 || st.EndPlace != nil {
		t.Errorf("replaced: %+v", st)
	}
	if code, body := owner.upload(base+"/stages/"+st2+"/import", "mailand.gpx", gpxDoc(line("Mailand", 9.19, 45.46, 5)), "replace", "true"); code != http.StatusUnprocessableEntity {
		t.Errorf("outside: %d %s", code, body)
	}

	// Viewers may not import; others do not see the journey.
	if code, _ := viewer.upload(base+"/stages/"+st1+"/import", "tag1.gpx", shorter, "replace", "true"); code != http.StatusForbidden {
		t.Errorf("viewer: %d, want 403", code)
	}
	if code, _ := stranger.upload(base+"/stages/"+st1+"/import", "tag1.gpx", shorter, "replace", "true"); code != http.StatusNotFound {
		t.Errorf("stranger: %d, want 404", code)
	}
}
