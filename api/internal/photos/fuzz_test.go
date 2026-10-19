package photos

import (
	"bytes"
	"image"
	"image/png"
	"math"
	"os"
	"testing"

	"github.com/tellbow/alvyo/api/internal/photos/phototest"
)

// FuzzProcess feeds Process what anyone can upload: it may refuse it, but
// what it takes comes out as a small JPEG with a sane position.
func FuzzProcess(f *testing.F) {
	f.Add(phototest.JPEG(40, 20, phototest.EXIF{Orientation: 6, DateTime: "2026:07:04 09:30:00", Lon: 8.0247, Lat: 46.6703}))
	var buf bytes.Buffer
	_ = png.Encode(&buf, image.NewRGBA(image.Rect(0, 0, 8, 6)))
	f.Add(buf.Bytes())
	if heic, err := os.ReadFile("testdata/geo.heic"); err == nil {
		f.Add(heic)
	}
	f.Fuzz(func(t *testing.T, data []byte) {
		p, err := Process(bytes.NewReader(data))
		if err != nil {
			return
		}
		if p.Width < 1 || p.Height < 1 || max(p.Width, p.Height) > LargePx || len(p.Large) == 0 || len(p.Thumb) == 0 {
			t.Fatalf("%d×%d, %d and %d bytes", p.Width, p.Height, len(p.Large), len(p.Thumb))
		}
		if bytes.Contains(p.Large, []byte("Exif")) {
			t.Fatal("EXIF kept")
		}
		if (p.Lon == nil) != (p.Lat == nil) {
			t.Fatal("half a position")
		}
		if p.Lon != nil && (math.IsNaN(*p.Lon) || math.IsNaN(*p.Lat) || math.Abs(*p.Lon) > 180 || math.Abs(*p.Lat) > 90) {
			t.Fatalf("position %v, %v", *p.Lon, *p.Lat)
		}
	})
}
