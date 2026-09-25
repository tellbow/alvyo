package photos

import (
	"bytes"
	"errors"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"math"
	"os"
	"runtime"
	"strings"
	"testing"

	"github.com/tellbow/alvyo/api/internal/photos/phototest"
)

func TestProcessJPEGWithEXIF(t *testing.T) {
	// 3000×1000, "rotate 90° clockwise to display", taken near Bachalpsee.
	src := phototest.JPEG(3000, 1000, phototest.EXIF{
		Orientation: 6, DateTime: "2026:07:04 09:30:00", Lon: 8.0247, Lat: 46.6703,
	})
	p, err := Process(bytes.NewReader(src))
	if err != nil {
		t.Fatal(err)
	}
	// Upright and scaled: 1000×3000 → 683×2048.
	if p.Width != 683 || p.Height != 2048 {
		t.Errorf("large %d×%d", p.Width, p.Height)
	}
	if p.Lon == nil || math.Abs(*p.Lon-8.0247) > 1e-5 || math.Abs(*p.Lat-46.6703) > 1e-5 {
		t.Errorf("position %v %v", p.Lon, p.Lat)
	}
	if p.TakenAt == nil || p.TakenAt.UTC().Format("2006-01-02 15:04") != "2026-07-04 07:30" {
		t.Errorf("taken at %v (want 09:30 Swiss summer time)", p.TakenAt)
	}
	for name, b := range map[string][]byte{"large": p.Large, "thumb": p.Thumb} {
		if bytes.Contains(b, []byte("Exif")) {
			t.Errorf("%s still has EXIF data", name)
		}
		img, err := jpeg.Decode(bytes.NewReader(b))
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		// The red quarter was top left; turned clockwise it is top right.
		bb := img.Bounds()
		if !red(img.At(bb.Max.X-bb.Dx()/8, bb.Min.Y+bb.Dy()/8)) || red(img.At(bb.Min.X+bb.Dx()/8, bb.Min.Y+bb.Dy()/8)) {
			t.Errorf("%s is not upright", name)
		}
	}
	thumb, _ := jpeg.DecodeConfig(bytes.NewReader(p.Thumb))
	if thumb.Height != ThumbPx {
		t.Errorf("thumb %d×%d", thumb.Width, thumb.Height)
	}
}

// TestProcessHEIC reads an iPhone-style HEIC: made with macOS sips from a
// 64×48 phototest JPEG with orientation 6, taken 2026-07-04 09:30 at
// 8.04, 46.66.
func TestProcessHEIC(t *testing.T) {
	src, err := os.ReadFile("testdata/geo.heic")
	if err != nil {
		t.Fatal(err)
	}
	p, err := Process(bytes.NewReader(src))
	if err != nil {
		t.Fatal(err)
	}
	if p.Width != 48 || p.Height != 64 {
		t.Errorf("large %d×%d, want upright 48×64", p.Width, p.Height)
	}
	if p.Lon == nil || math.Abs(*p.Lon-8.04) > 1e-4 || math.Abs(*p.Lat-46.66) > 1e-4 {
		t.Errorf("position %v %v", p.Lon, p.Lat)
	}
	if p.TakenAt == nil || p.TakenAt.UTC().Format("2006-01-02 15:04") != "2026-07-04 07:30" {
		t.Errorf("taken at %v", p.TakenAt)
	}
	img, err := jpeg.Decode(bytes.NewReader(p.Large))
	if err != nil {
		t.Fatal(err)
	}
	// Turned clockwise, the red quarter is top right.
	bb := img.Bounds()
	if !red(img.At(bb.Max.X-bb.Dx()/8, bb.Min.Y+bb.Dy()/8)) || red(img.At(bb.Min.X+bb.Dx()/8, bb.Min.Y+bb.Dy()/8)) {
		t.Error("not upright")
	}
	if bytes.Contains(p.Large, []byte("Exif")) {
		t.Error("EXIF data kept")
	}
}

func red(c color.Color) bool {
	r, g, b, _ := c.RGBA()
	return r > 0xc000 && g < 0x4000 && b < 0x4000
}

func TestProcessOtherInput(t *testing.T) {
	// A small PNG stays as it is (re-encoded), without position or time.
	var buf bytes.Buffer
	_ = png.Encode(&buf, image.NewRGBA(image.Rect(0, 0, 40, 30)))
	p, err := Process(&buf)
	if err != nil || p.Width != 40 || p.Height != 30 || p.Lon != nil || p.TakenAt != nil {
		t.Errorf("png: %+v %v", p, err)
	}
	if _, err := Process(strings.NewReader("<svg/>")); !errors.Is(err, ErrFormat) {
		t.Errorf("svg: %v", err)
	}
	// A JPEG claiming 9000×9000 pixels is refused before decoding.
	b := phototest.JPEG(16, 16, phototest.EXIF{})
	i := bytes.Index(b, []byte{0xFF, 0xC0})
	copy(b[i+5:], []byte{0x23, 0x28, 0x23, 0x28})
	if _, err := Process(bytes.NewReader(b)); !errors.Is(err, ErrTooLarge) {
		t.Errorf("9000×9000: %v", err)
	}
}

func TestProcessCraftedEXIF(t *testing.T) {
	// An orientation that claims 2³¹+1 values: goexif would allocate 16 GiB
	// for it. The photo is taken, without its EXIF data.
	tiff := []byte("II*\x00\x08\x00\x00\x00" + // little endian, IFD0 at 8
		"\x01\x00" + // one entry
		"\x12\x01\x03\x00\x01\x00\x00\x80\x00\x00\x00\x00" + // 0x0112 SHORT ×(2³¹+1)
		"\x00\x00\x00\x00") // no next IFD
	if saneTIFF(tiff) {
		t.Fatal("crafted count accepted")
	}
	var img bytes.Buffer
	_ = jpeg.Encode(&img, image.NewRGBA(image.Rect(0, 0, 64, 48)), nil)
	seg := append([]byte("Exif\x00\x00"), tiff...)
	app1 := append([]byte{0xFF, 0xE1, byte((len(seg) + 2) >> 8), byte(len(seg) + 2)}, seg...)
	jpg := append(append(append([]byte{}, img.Bytes()[:2]...), app1...), img.Bytes()[2:]...)
	if exifTIFF(jpg) == nil {
		t.Fatal("EXIF segment not found")
	}

	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	p, err := Process(bytes.NewReader(jpg))
	runtime.ReadMemStats(&after)
	if err != nil || p.Lon != nil || p.Width != 64 {
		t.Errorf("process: %v %+v", err, p)
	}
	if grew := after.TotalAlloc - before.TotalAlloc; grew > 64<<20 {
		t.Errorf("allocated %d MiB", grew>>20)
	}
}
