package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"strings"
	"testing"

	"github.com/tellbow/alvyo/api/internal/imports"
	"github.com/tellbow/alvyo/api/internal/routing"
	"github.com/tellbow/alvyo/swiss/geo"
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

func newImportServer(t *testing.T) *testServer {
	return newTestServerWith(t, func(d *Deps) {
		router := &routing.Router{Elevation: flatSampler{}, Trails: &routing.TrailMatcher{DB: d.DB}}
		d.Importer = &imports.Importer{Router: router, Routes: d.Routes, Journeys: d.Journeys}
	})
}

type importResp struct {
	Routes []struct {
		ID    string `json:"id"`
		Title string `json:"title"`
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
	s := newImportServer(t)
	c := s.client(t)
	file := gpxDoc(line("Tag 1", 8.00, 46.66, 30), line("Tag 2", 8.03, 46.66, 30), line("Mailand", 9.19, 45.46, 5))

	if code, _ := c.upload("/api/v1/imports/preview", "tour.gpx", file); code != http.StatusUnauthorized {
		t.Errorf("anonymous preview: %d, want 401", code)
	}
	s.signup(c, "importer@example.ch", "importer")
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
	s.signup(other, "other@example.ch", "other")
	if code, _ := other.do("GET", "/api/v1/journeys/"+r.JourneyID, nil); code != http.StatusNotFound {
		t.Errorf("other user sees the imported journey: %d", code)
	}
}

func TestImportIntoStage(t *testing.T) {
	s := newImportServer(t)
	var stop string
	if err := s.db.QueryRow(context.Background(), `INSERT INTO places (kind, name, source, source_id, geom)
		VALUES ('pt_stop', 'Faulhorn', 'didok', '1', ST_SetSRID(ST_MakePoint(8.059, 46.66), 4326)) RETURNING id`).Scan(&stop); err != nil {
		t.Fatal(err)
	}
	owner, viewer, stranger := s.client(t), s.client(t), s.client(t)
	s.signup(owner, "stages@example.ch", "stages")
	s.signup(viewer, "vie@example.ch", "vie")
	s.signup(stranger, "str@example.ch", "str")
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

// recordedDay is a GPX track segment of a day's walk east from lon at
// 46.66° N, 30 points recorded from 08:00 on date, a minute apart.
func recordedDay(lon float64, date string) string {
	var b strings.Builder
	for i := range 30 {
		fmt.Fprintf(&b, `<trkpt lat="46.66" lon="%f"><time>%sT08:%02d:00Z</time></trkpt>`, lon+float64(i)*0.001, date, i)
	}
	return b.String()
}

func TestImportStages(t *testing.T) {
	gh := straightGraphHopper(t)
	s := newTestServerWith(t, func(d *Deps) {
		router := &routing.Router{GraphHopper: &routing.GraphHopper{URL: gh}, Elevation: flatSampler{}, Trails: &routing.TrailMatcher{DB: d.DB}}
		d.Importer = &imports.Importer{Router: router, Routes: d.Routes, Journeys: d.Journeys}
	})
	place := func(kind, name string, lon float64) string {
		var id string
		if err := s.db.QueryRow(context.Background(), `INSERT INTO places (kind, name, source, source_id, geom)
			VALUES ($1, $2, 'osm', $2, ST_SetSRID(ST_MakePoint($3, 46.6605), 4326)) RETURNING id`, kind, name, lon).Scan(&id); err != nil {
			t.Fatal(err)
		}
		return id
	}
	hut := place("hut", "Tageshütte", 8.0295) // where day 1 ends
	inn := place("hotel", "Gasthaus Mitte", 8.045)

	recording := gpxDoc(`<trk><name>Drei Tage</name><trkseg>` + recordedDay(8.00, "2026-07-04") +
		recordedDay(8.03, "2026-07-05") + recordedDay(8.06, "2026-07-06") + `</trkseg></trk>`)
	c := s.client(t)
	if code, _ := c.upload("/api/v1/imports/stages", "drei.gpx", recording); code != http.StatusUnauthorized {
		t.Errorf("anonymous: %d", code)
	}
	s.signup(c, "stager@example.ch", "stager")
	code, body := c.upload("/api/v1/imports/preview", "drei.gpx", recording)
	var preview struct{ Tracks []trackSummary }
	_ = json.Unmarshal(body, &preview)
	if code != http.StatusOK || len(preview.Tracks) != 1 || preview.Tracks[0].Nights != 2 {
		t.Fatalf("preview: %d %s", code, body)
	}

	stages := func(code int, body []byte) proposal {
		t.Helper()
		if code != http.StatusOK {
			t.Fatalf("stages: %d %s", code, body)
		}
		var p proposal
		_ = json.Unmarshal(body, &p)
		return p
	}

	// A stage per day of the recording; the first night at the hut.
	p := stages(c.upload("/api/v1/imports/stages", "drei.gpx", recording))
	if len(p.Stages) != 3 || p.Stages[0].EndPlace == nil || p.Stages[0].EndPlace.ID != hut ||
		p.Stages[0].Accommodation != "Tageshütte" || p.Stages[1].StartPlace == nil || p.Stages[1].StartPlace.ID != hut ||
		p.Stages[1].EndPlace != nil || p.Stages[2].EndPlace != nil {
		t.Fatalf("stages: %+v", p.Stages)
	}
	var created []map[string]any
	for _, st := range p.Stages {
		s := map[string]any{"profile": st.Profile, "anchors": st.Anchors, "legs": st.Legs, "accommodation": st.Accommodation}
		if st.EndPlace != nil {
			s["end_place_id"] = st.EndPlace.ID
		}
		created = append(created, s)
	}
	code, body = c.do("POST", "/api/v1/journeys", map[string]any{"title": "Drei Tage", "stages": created})
	if j := decodeJourney(t, body); code != http.StatusCreated || len(j.StageList) != 3 || j.StageList[2].Route == nil {
		t.Fatalf("journey: %d %s", code, body)
	}

	// A planned route has no nights: it is split by the days asked for, at
	// the guest house half way.
	planned := gpxDoc(line("Weg", 8.0, 46.66, 91))
	if code, body := c.upload("/api/v1/imports/stages", "weg.gpx", planned); code != http.StatusUnprocessableEntity {
		t.Errorf("no nights, no days: %d %s", code, body)
	}
	p = stages(c.upload("/api/v1/imports/stages", "weg.gpx", planned, "days", "2"))
	if len(p.Stages) != 2 || p.Stages[0].EndPlace == nil || p.Stages[0].EndPlace.ID != inn {
		t.Errorf("two days: %+v", p.Stages)
	}
	// The same split for a recording when days are given.
	if p = stages(c.upload("/api/v1/imports/stages", "drei.gpx", recording, "days", "2")); len(p.Stages) != 2 {
		t.Errorf("recording in two days: %d stages", len(p.Stages))
	}
	if code, _ := c.upload("/api/v1/imports/stages", "weg.gpx", planned, "days", "2", "ends", "nope"); code != http.StatusUnprocessableEntity {
		t.Errorf("bad end: %d", code)
	}
}

// offLineSampler has no elevations north of the line: the way to a place
// beside it fails, the line itself does not.
type offLineSampler struct{}

func (offLineSampler) Sample(_ context.Context, pts []geo.Point) ([]float64, error) {
	for _, p := range pts {
		if p.Lat > 46.6602 {
			return nil, errors.New("geo.admin down")
		}
	}
	return make([]float64, len(pts)), nil
}

// The way to a night's place failing for elevations is a 503 to retry, as
// in the planner, not an internal error.
func TestImportStagesElevationDown(t *testing.T) {
	gh := straightGraphHopper(t)
	s := newTestServerWith(t, func(d *Deps) {
		router := &routing.Router{GraphHopper: &routing.GraphHopper{URL: gh}, Elevation: offLineSampler{}, Trails: &routing.TrailMatcher{DB: d.DB}}
		d.Importer = &imports.Importer{Router: router, Routes: d.Routes, Journeys: d.Journeys}
	})
	if _, err := s.db.Exec(context.Background(), `INSERT INTO places (kind, name, source, source_id, geom)
		VALUES ('hotel', 'Gasthaus', 'osm', 'g', ST_SetSRID(ST_MakePoint(8.045, 46.6605), 4326))`); err != nil {
		t.Fatal(err)
	}
	c := s.client(t)
	s.signup(c, "down@example.ch", "down")
	planned := gpxDoc(line("Weg", 8.0, 46.66, 91))
	if code, body := c.upload("/api/v1/imports/stages", "weg.gpx", planned, "days", "2"); code != http.StatusServiceUnavailable {
		t.Errorf("elevations down: %d %s", code, body)
	}
}
