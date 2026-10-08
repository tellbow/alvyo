package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/tellbow/alvyo/api/internal/imports"
	"github.com/tellbow/alvyo/api/internal/photos"
	"github.com/tellbow/alvyo/api/internal/photos/phototest"
	"github.com/tellbow/alvyo/api/internal/routing"
	"github.com/tellbow/alvyo/swiss/geo"
)

type lineResp struct {
	Anchors []struct{ Lon, Lat float64 } `json:"anchors"`
	Legs    []struct {
		Coordinates [][3]float64 `json:"coordinates"`
	} `json:"legs"`
}

func (r lineResp) ends() (first, last geo.Point) {
	if len(r.Legs) == 0 {
		return
	}
	l := r.Legs[len(r.Legs)-1].Coordinates
	return geo.Point{Lon: r.Legs[0].Coordinates[0][0], Lat: r.Legs[0].Coordinates[0][1]},
		geo.Point{Lon: l[len(l)-1][0], Lat: l[len(l)-1][1]}
}

func TestHikePrivacy(t *testing.T) {
	dir := t.TempDir()
	s := newTestServerWith(t, func(d *Deps) {
		router := &routing.Router{Elevation: flatSampler{}, Trails: &routing.TrailMatcher{DB: d.DB}}
		d.Importer = &imports.Importer{Router: router, Routes: d.Routes, Journeys: d.Journeys}
		d.Photos = &photos.Store{DB: d.DB, Files: &photos.Files{Dir: dir}}
	})
	ctx := context.Background()
	owner := s.client(t)
	s.signup(owner, "hiker@example.ch", "hiker")
	if _, err := s.db.Exec(ctx, `UPDATE users SET email_verified_at = now()`); err != nil {
		t.Fatal(err)
	}
	start := time.Date(2026, 9, 23, 8, 0, 0, 0, time.UTC)
	upload := func(id string, lon0 float64, points int) string {
		t.Helper()
		b := hikeBody(id, "", lon0, start)
		b["points"] = b["points"].([]map[string]any)[:points]
		code, body := owner.do("POST", "/api/v1/hikes", b)
		var up struct{ ID string }
		if err := json.Unmarshal(body, &up); code != http.StatusCreated || err != nil {
			t.Fatalf("upload: %d %s", code, body)
		}
		if code, body := owner.do("PATCH", "/api/v1/routes/"+up.ID, map[string]any{"visibility": "public"},
			"If-Match", `"1"`); code != http.StatusOK {
			t.Fatalf("public: %d %s", code, body)
		}
		return up.ID
	}
	// 2 km east from 8.0, and one of 600 m.
	long, short := upload("rec-long", 8.0, 100), upload("rec-short", 8.1, 31)
	hikeStart, hikeEnd := geo.Point{Lon: 8.0, Lat: 46.5}, geo.Point{Lon: 8.0 + 99*20.0/76_600, Lat: 46.5}

	get := func(c *client, id string) lineResp {
		t.Helper()
		code, body := c.do("GET", "/api/v1/routes/"+id, nil)
		var r lineResp
		if err := json.Unmarshal(body, &r); code != http.StatusOK || err != nil {
			t.Fatalf("get: %d %s", code, body)
		}
		return r
	}
	first, last := get(owner, long).ends()
	if geo.Distance(first, hikeStart) > 5 || geo.Distance(last, hikeEnd) > 5 {
		t.Errorf("the owner sees all of it: %v … %v", first, last)
	}

	anon := s.client(t)
	seen := get(anon, long)
	first, last = seen.ends()
	if d := geo.Distance(first, hikeStart); d <= 500 || d > 540 {
		t.Errorf("others' line starts %.0f m from the start", d)
	}
	if d := geo.Distance(last, hikeEnd); d <= 500 || d > 540 {
		t.Errorf("others' line ends %.0f m from the end", d)
	}
	if a := seen.Anchors[0]; geo.Distance(geo.Point{Lon: a.Lon, Lat: a.Lat}, hikeStart) <= 500 {
		t.Errorf("first anchor at the start: %+v", a)
	}
	if len(seen.Anchors) != len(seen.Legs)+1 {
		t.Errorf("%d anchors for %d legs", len(seen.Anchors), len(seen.Legs))
	}
	if r := get(anon, short); len(r.Legs) != 0 || len(r.Anchors) != 0 {
		t.Errorf("600 m: nothing to show, got %d legs", len(r.Legs))
	}

	// Photos taken near the start are in the gallery, not on the map.
	for _, lon := range []float64{8.001, 8.013} {
		img := phototest.JPEG(80, 60, phototest.EXIF{Lon: lon, Lat: 46.5})
		if code, _ := owner.uploadPhoto("/api/v1/routes/"+long+"/photos", img, ""); code != http.StatusOK {
			t.Fatalf("photo: %d", code)
		}
	}
	pins := func(c *client) (n int) {
		_, ps := c.photos("/api/v1/routes/" + long + "/photos")
		for _, p := range ps.Photos {
			if p.Pin != nil {
				n++
			}
		}
		if len(ps.Photos) != 2 {
			t.Fatalf("photos: %+v", ps)
		}
		return n
	}
	if o, a := pins(owner), pins(anon); o != 2 || a != 1 {
		t.Errorf("pins: the owner sees %d, others %d", o, a)
	}

	_, gpx := anon.do("GET", "/api/v1/routes/"+long+"/gpx", nil)
	if strings.Contains(string(gpx), `lon="8.000000"`) || !strings.Contains(string(gpx), "<trkpt") {
		t.Errorf("GPX from the start: %.300s", gpx)
	}

	// On the maps: discover (anyone), and a collection of someone else.
	_, body := anon.do("GET", "/api/v1/discover?bbox=7.99,46.49,8.12,46.51", nil)
	var found discoverResp
	_ = json.Unmarshal(body, &found)
	lines := map[string][][][2]float64{}
	for _, it := range found.Items {
		lines[it.ID] = it.Lines
	}
	if l := lines[long]; len(l) != 1 || geo.Distance(geo.Point{Lon: l[0][0][0], Lat: l[0][0][1]}, hikeStart) <= 500 {
		t.Errorf("discover: %v", l)
	}
	if _, ok := lines[short]; ok {
		t.Errorf("discover, 600 m: nothing to show, but listed")
	}
	// A view of the hidden start alone finds nothing: else views could
	// narrow down where it lies.
	_, body = anon.do("GET", "/api/v1/discover?bbox=7.999,46.499,8.002,46.501", nil)
	found = discoverResp{}
	_ = json.Unmarshal(body, &found)
	for _, it := range found.Items {
		if it.ID == long {
			t.Errorf("discover: found by its hidden start")
		}
	}

	other := s.client(t)
	s.signup(other, "other@example.ch", "other")
	_, body = other.do("POST", "/api/v1/collections", map[string]any{"title": "Ideen", "visibility": "private"})
	var col struct{ ID string }
	_ = json.Unmarshal(body, &col)
	if code, body := other.do("POST", "/api/v1/collections/"+col.ID+"/items", map[string]any{"route_id": long}); code >= 300 {
		t.Fatalf("add: %d %s", code, body)
	}
	_, body = other.do("GET", "/api/v1/collections/"+col.ID, nil)
	var c struct {
		Items []struct {
			Lines [][][2]float64 `json:"lines"`
		} `json:"item_list"`
	}
	_ = json.Unmarshal(body, &c)
	if len(c.Items) != 1 || len(c.Items[0].Lines) != 1 ||
		geo.Distance(geo.Point{Lon: c.Items[0].Lines[0][0][0], Lat: 46.5}, hikeStart) <= 500 {
		t.Errorf("collection: %s", body)
	}
}
