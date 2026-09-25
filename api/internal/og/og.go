// Package og renders social preview images (Open Graph, 1200×630) of routes,
// journeys and collections: their lines on the swisstopo national map with
// the title and key numbers.
package og

import (
	"bytes"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"math"
	"os"
	"path/filepath"
	"strings"

	sm "github.com/flopp/go-staticmaps"
	"github.com/golang/geo/s2"
	"golang.org/x/image/font"
	"golang.org/x/image/font/gofont/gobold"
	"golang.org/x/image/font/gofont/goregular"
	"golang.org/x/image/font/opentype"
	"golang.org/x/image/math/fixed"
	"golang.org/x/sync/singleflight"
)

// Image size recommended for Open Graph previews.
const (
	Width     = 1200
	Height    = 630
	bandH     = 120 // text band below the map
	maxPoints = 2000
)

var routeColor = color.RGBA{0xa2, 0x1c, 0xaf, 0xff}

// Style is part of the cache key of the images: raise it when their look
// changes, so no image drawn before is served again.
const Style = 2

// The text band in the colours of the website's dark mode.
var (
	ground = color.RGBA{0x0e, 0x15, 0x12, 0xff}
	accent = color.RGBA{0xff, 0xa6, 0x6b, 0xff}
)

// Card is what the image shows.
type Card struct {
	Title string
	Stats string // e.g. "12.3 km · 4 h 15 min · ↑ 850 m · T3"
	// Lines are (lon, lat) lines: a route's, a journey's stages, a
	// collection's items.
	Lines [][][2]float64
	// Ends marks the start of the first line and the end of the last.
	Ends bool
}

// Renderer draws cards and caches them as PNG files.
type Renderer struct {
	TilesURL string // our tile cache, e.g. http://tilecache:8080
	CacheDir string
	group    singleflight.Group
}

// PNG returns the image for key ("<id>-<version>"), rendering it once.
// The images of the item's other versions are removed then.
func (r *Renderer) PNG(key string, card Card) ([]byte, error) {
	path := filepath.Join(r.CacheDir, "og", key+".png")
	if b, err := os.ReadFile(path); err == nil {
		return b, nil
	}
	v, err, _ := r.group.Do(key, func() (any, error) {
		b, err := r.render(card)
		if err != nil {
			return nil, err
		}
		if err := writeAtomic(path, b); err != nil {
			return nil, err
		}
		if i := strings.LastIndex(key, "-"); i > 0 {
			old, _ := filepath.Glob(filepath.Join(r.CacheDir, "og", key[:i+1]+"*.png"))
			for _, p := range old {
				if p != path {
					_ = os.Remove(p)
				}
			}
		}
		return b, nil
	})
	if err != nil {
		return nil, err
	}
	return v.([]byte), nil
}

func (r *Renderer) render(card Card) ([]byte, error) {
	points := 0
	for _, l := range card.Lines {
		points += len(l)
	}
	if points < 2 {
		return nil, fmt.Errorf("og: no line")
	}
	ctx := sm.NewContext()
	ctx.SetSize(Width, Height-bandH)
	ctx.SetCache(nil) // tiles come through our own caching proxy
	ctx.SetUserAgent("alvyo-og")
	ctx.SetTileProvider(&sm.TileProvider{
		Name:        "swisstopo",
		Attribution: "© swisstopo, © OpenStreetMap contributors",
		TileSize:    256,
		URLPattern:  strings.TrimSuffix(r.TilesURL, "/") + "/tiles/wmts/ch.swisstopo.pixelkarte-farbe/%[2]d/%[3]d/%[4]d.jpeg",
	})

	step := max(1, points/maxPoints)
	var paths [][]s2.LatLng
	for _, l := range card.Lines {
		if len(l) < 2 {
			continue
		}
		var pos []s2.LatLng
		for i := 0; i < len(l); i += step {
			pos = append(pos, s2.LatLngFromDegrees(l[i][1], l[i][0]))
		}
		last := l[len(l)-1]
		paths = append(paths, append(pos, s2.LatLngFromDegrees(last[1], last[0])))
	}
	// All white casings first: a line is never hidden under another's.
	for _, pos := range paths {
		ctx.AddObject(sm.NewPath(pos, color.White, 10))
	}
	for _, pos := range paths {
		ctx.AddObject(sm.NewPath(pos, routeColor, 6))
	}
	if card.Ends && len(paths) > 0 {
		first, last := paths[0], paths[len(paths)-1]
		ctx.AddObject(sm.NewMarker(first[0], color.RGBA{0x16, 0xa3, 0x4a, 0xff}, 18))
		ctx.AddObject(sm.NewMarker(last[len(last)-1], routeColor, 18))
	}

	mapImg, err := ctx.Render()
	if err != nil {
		return nil, fmt.Errorf("og: map: %w", err)
	}

	img := image.NewRGBA(image.Rect(0, 0, Width, Height))
	draw.Draw(img, img.Bounds(), image.NewUniform(ground), image.Point{}, draw.Src)
	draw.Draw(img, image.Rect(0, 0, Width, Height-bandH), mapImg, image.Point{}, draw.Src)
	if err := drawText(img, card); err != nil {
		return nil, err
	}

	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func drawText(img *image.RGBA, card Card) error {
	bold, err := face(gobold.TTF, 44)
	if err != nil {
		return err
	}
	regular, err := face(goregular.TTF, 28)
	if err != nil {
		return err
	}
	ink := image.NewUniform(color.RGBA{0xe9, 0xef, 0xe9, 0xff})
	muted := image.NewUniform(color.RGBA{0xa4, 0xb2, 0xa9, 0xff})
	top := Height - bandH

	title := truncate(bold, card.Title, Width-64-200)
	(&font.Drawer{Dst: img, Src: ink, Face: bold, Dot: fixed.P(32, top+52)}).DrawString(title)
	(&font.Drawer{Dst: img, Src: muted, Face: regular, Dot: fixed.P(32, top+96)}).DrawString(card.Stats)
	brand := "Alvyo"
	w := font.MeasureString(bold, brand).Ceil()
	(&font.Drawer{Dst: img, Src: image.NewUniform(accent), Face: bold, Dot: fixed.P(Width-32-w, top+52)}).DrawString(brand)
	return nil
}

func face(ttf []byte, size float64) (font.Face, error) {
	f, err := opentype.Parse(ttf)
	if err != nil {
		return nil, err
	}
	return opentype.NewFace(f, &opentype.FaceOptions{Size: size, DPI: 72, Hinting: font.HintingFull})
}

// truncate shortens s with an ellipsis so it fits into width pixels.
func truncate(f font.Face, s string, width int) string {
	if font.MeasureString(f, s).Ceil() <= width {
		return s
	}
	r := []rune(s)
	for len(r) > 0 && font.MeasureString(f, string(r)+"…").Ceil() > width {
		r = r[:len(r)-1]
	}
	return string(r) + "…"
}

func writeAtomic(path string, b []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".og-*")
	if err != nil {
		return err
	}
	if _, err := tmp.Write(b); err != nil {
		_ = tmp.Close()
		_ = os.Remove(tmp.Name())
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}

// Duration formats seconds like Swiss signposts: rounded to 5 minutes.
func Duration(seconds int) string {
	minutes := int(math.Round(float64(seconds)/60/5)) * 5
	h, m := minutes/60, minutes%60
	switch {
	case h == 0:
		return fmt.Sprintf("%d min", m)
	case m == 0:
		return fmt.Sprintf("%d h", h)
	default:
		return fmt.Sprintf("%d h %d min", h, m)
	}
}
