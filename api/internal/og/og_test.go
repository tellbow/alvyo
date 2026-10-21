package og

import (
	"bytes"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"

	"golang.org/x/image/font/gofont/goregular"
)

func tileServer(t *testing.T) (*httptest.Server, *atomic.Int32) {
	var n atomic.Int32
	tile := image.NewRGBA(image.Rect(0, 0, 256, 256))
	for i := range tile.Pix {
		tile.Pix[i] = 0xee
	}
	var buf bytes.Buffer
	_ = jpeg.Encode(&buf, tile, nil)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		n.Add(1)
		w.Header().Set("Content-Type", "image/jpeg")
		_, _ = w.Write(buf.Bytes())
	}))
	t.Cleanup(srv.Close)
	return srv, &n
}

func TestRenderAndCache(t *testing.T) {
	srv, requests := tileServer(t)
	r := &Renderer{TilesURL: srv.URL, CacheDir: t.TempDir()}
	card := Card{
		Title: "Via Alpina 1: Gaflei – Sargans, a title long enough to need shortening somewhere",
		Stats: "18.7 km · 4 h 45 min · ↑ 35 m ↓ 990 m · T2–T3",
		Lines: [][][2]float64{{{9.5428, 47.1447}, {9.50, 47.10}, {9.4456, 47.0449}}},
		Ends:  true,
	}
	b, err := r.PNG("route-1", card)
	if err != nil {
		t.Fatal(err)
	}
	img, err := png.Decode(bytes.NewReader(b))
	if err != nil {
		t.Fatal(err)
	}
	if img.Bounds().Dx() != Width || img.Bounds().Dy() != Height {
		t.Errorf("size %v", img.Bounds())
	}
	if requests.Load() == 0 {
		t.Error("no tiles requested")
	}
	// The route's midpoint is drawn in the route colour somewhere near the
	// map centre.
	if !hasColor(img, routeColor, image.Rect(Width/2-100, 0, Width/2+100, Height-bandH)) {
		t.Error("route line not found in the map area")
	}

	before := requests.Load()
	if _, err := r.PNG("route-1", card); err != nil {
		t.Fatal(err)
	}
	if requests.Load() != before {
		t.Error("second call rendered again instead of using the cache")
	}

	// A new version of the route: the old image goes, not to fill the cache.
	if _, err := r.PNG("route-2", card); err != nil {
		t.Fatal(err)
	}
	left, _ := filepath.Glob(filepath.Join(r.CacheDir, "og", "*.png"))
	if len(left) != 1 || filepath.Base(left[0]) != "route-2.png" {
		t.Errorf("cached images %v", left)
	}
}

func hasColor(img image.Image, want color.RGBA, area image.Rectangle) bool {
	for y := area.Min.Y; y < area.Max.Y; y++ {
		for x := area.Min.X; x < area.Max.X; x++ {
			r, g, b, _ := img.At(x, y).RGBA()
			if uint8(r>>8) == want.R && uint8(g>>8) == want.G && uint8(b>>8) == want.B {
				return true
			}
		}
	}
	return false
}

func TestDuration(t *testing.T) {
	for in, want := range map[int]string{600: "10 min", 3600: "1 h", 3*3600 + 23*60: "3 h 25 min"} {
		if got := Duration(in); got != want {
			t.Errorf("Duration(%d) = %q, want %q", in, got, want)
		}
	}
}

// Lines across all of Switzerland: zoom 8, not further out than the
// swisstopo map reaches.
func TestRenderSwitzerland(t *testing.T) {
	tile := image.NewRGBA(image.Rect(0, 0, 256, 256))
	var buf bytes.Buffer
	_ = jpeg.Encode(&buf, tile, nil)
	var zooms sync.Map
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		zooms.Store(strings.Split(strings.TrimPrefix(r.URL.Path, "/tiles/wmts/ch.swisstopo.pixelkarte-farbe/"), "/")[0], true)
		w.Header().Set("Content-Type", "image/jpeg")
		_, _ = w.Write(buf.Bytes())
	}))
	t.Cleanup(srv.Close)
	r := &Renderer{TilesURL: srv.URL, CacheDir: t.TempDir()}
	card := Card{Title: "Schweiz", Lines: [][][2]float64{{{5.96, 46.13}, {8.6, 47.8}, {9.0, 45.82}, {10.49, 46.6}}}, Credit: "ASTRA / SchweizMobil"}
	if _, err := r.PNG("ch-1", card); err != nil {
		t.Fatal(err)
	}
	zooms.Range(func(z, _ any) bool {
		if z != "8" {
			t.Errorf("tiles at zoom %s", z)
		}
		return true
	})
}

// The credit's font has «©» (the map library's has not).
func TestCreditFontHasCopyright(t *testing.T) {
	f, err := face(goregular.TTF, 15)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := f.GlyphAdvance('©'); !ok {
		t.Error("no ©")
	}
}
