package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
)

func TestSnowCover(t *testing.T) {
	s := newTestServer(t, Limits{})
	anon := s.client(t)
	ctx := context.Background()
	var cover struct {
		Date, Tiles      string
		MinZoom, MaxZoom int
		Legend           []struct {
			From  int
			Color string
		}
		Attribution string
	}
	get := func() {
		t.Helper()
		code, body := anon.do("GET", "/api/v1/weather/snow", nil)
		cover.Date, cover.Tiles = "", ""
		if err := json.Unmarshal(body, &cover); err != nil || code != http.StatusOK {
			t.Fatalf("snow cover: %d %s", code, body)
		}
	}

	// None yet: no day, the legend and credit all the same.
	get()
	if cover.Date != "" || cover.Tiles != "" || len(cover.Legend) != 3 || cover.Attribution == "" {
		t.Fatalf("without snow cover: %+v", cover)
	}

	if _, err := s.db.Exec(ctx, `INSERT INTO snow_days (day) VALUES ('2026-10-18');
		INSERT INTO snow_tiles (day, z, x, y, png) VALUES ('2026-10-18', 9, 266, 180, 'PNG')`); err != nil {
		t.Fatal(err)
	}
	get()
	if cover.Date != "2026-10-18" || cover.Tiles != "/api/v1/weather/snow/2026-10-18/{z}/{x}/{y}/tile.png" ||
		cover.MinZoom != 6 || cover.MaxZoom != 11 {
		t.Fatalf("snow cover: %+v", cover)
	}
	// A tile with snow; none without (no content: an empty tile); no day.
	if code, body := anon.do("GET", "/api/v1/weather/snow/2026-10-18/9/266/180/tile.png", nil); code != http.StatusOK || string(body) != "PNG" {
		t.Errorf("tile: %d %q", code, body)
	}
	if code, body := anon.do("GET", "/api/v1/weather/snow/2026-10-18/9/1/1/tile.png", nil); code != http.StatusNoContent || len(body) != 0 {
		t.Errorf("tile without snow: %d %q", code, body)
	}
	if code, _ := anon.do("GET", "/api/v1/weather/snow/2026-10-17/9/266/180/tile.png", nil); code != http.StatusNotFound {
		t.Errorf("an old day: %d", code)
	}
	if code, _ := anon.do("GET", "/api/v1/weather/snow/gestern/9/266/180/tile.png", nil); code != http.StatusUnprocessableEntity {
		t.Errorf("not a day: %d", code)
	}
}
