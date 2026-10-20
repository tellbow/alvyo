package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"math"
	"net/http"
	"testing"

	"github.com/tellbow/alvyo/api/internal/snow"
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

// allSnow puts snow on all of the tile of the test routes (8.0, 46.5), on
// 2026-10-18.
func allSnow(t *testing.T, s *testServer) {
	t.Helper()
	ctx := context.Background()
	n := math.Exp2(snow.MaxZoom)
	lat := 46.5 * math.Pi / 180
	x, y := int((8.0+180)/360*n), int((1-math.Log(math.Tan(lat)+1/math.Cos(lat))/math.Pi)/2*n)
	img := image.NewPaletted(image.Rect(0, 0, 256, 256), color.Palette{color.Transparent, color.White, color.White, color.White})
	for i := range img.Pix {
		img.Pix[i] = 3
	}
	var tile bytes.Buffer
	_ = png.Encode(&tile, img)
	if _, err := s.db.Exec(ctx, `INSERT INTO snow_days (day) VALUES ('2026-10-18')`); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(ctx, `INSERT INTO snow_tiles (day, z, x, y, png) VALUES ('2026-10-18', $1, $2, $3, $4)`,
		snow.MaxZoom, x, y, tile.Bytes()); err != nil {
		t.Fatal(err)
	}
}

func TestSnowAlong(t *testing.T) {
	s := newTestServer(t, Limits{})
	owner, other := s.client(t), s.client(t)
	s.signup(owner, "owner@example.ch", "owner")
	s.signup(other, "other@example.ch", "other")
	get := func(c *client, method, path string, body any) (int, snow.Along) {
		t.Helper()
		code, raw := c.do(method, path, body)
		var a snow.Along
		_ = json.Unmarshal(raw, &a)
		return code, a
	}

	allSnow(t, s)

	// A line in the planner: for those logged in.
	line := [][2]float64{{8.0, 46.5}, {8.004, 46.5}}
	if code, _ := get(s.client(t), "POST", "/api/v1/routing/snow", map[string]any{"line": line}); code != http.StatusUnauthorized {
		t.Errorf("anonymous: %d", code)
	}
	code, a := get(owner, "POST", "/api/v1/routing/snow", map[string]any{"line": line})
	if code != http.StatusOK || a.Date != "2026-10-18" || a.SnowM < 300 || len(a.Stretches) != 1 || a.Slopes || a.Attribution == "" {
		t.Fatalf("line: %d %+v", code, a)
	}
	if code, _ := get(owner, "POST", "/api/v1/routing/snow", map[string]any{"line": [][2]float64{{6, 46}, {10, 47}, {6, 46}, {10, 47}}}); code != http.StatusUnprocessableEntity {
		t.Errorf("too long a line: %d", code)
	}

	// A saved route: only for those who may see it.
	_, raw := owner.do("POST", "/api/v1/routes", newRouteBody("Im Schnee", "private"))
	var route savedRoute
	_ = json.Unmarshal(raw, &route)
	if code, a := get(owner, "GET", "/api/v1/routes/"+route.ID+"/snow", nil); code != http.StatusOK || a.SnowM < 300 || len(a.Stretches) != 1 {
		t.Errorf("route: %d %+v", code, a)
	}
	if code, _ := get(other, "GET", "/api/v1/routes/"+route.ID+"/snow", nil); code != http.StatusNotFound {
		t.Errorf("other's route: %d", code)
	}

	// A journey: the stretches with their stage.
	_, raw = owner.do("POST", "/api/v1/journeys", map[string]any{"title": "Zwei Tage"})
	jr := "/api/v1/journeys/" + decodeJourney(t, raw).ID
	for i := range 3 {
		_, raw = owner.do("POST", jr+"/stages", map[string]any{})
		if i < 2 { // the third stage has no route
			st := decodeJourney(t, raw).StageList[i].ID
			owner.do("POST", jr+"/stages/"+st+"/route", stageRouteBody(8.0+float64(i)*0.002))
		}
	}
	code, a = get(owner, "GET", jr+"/snow", nil)
	if code != http.StatusOK || a.Date != "2026-10-18" || len(a.Stretches) != 2 || a.Stretches[0].Stage != 1 || a.Stretches[1].Stage != 2 {
		t.Errorf("journey: %d %+v", code, a)
	}
}
