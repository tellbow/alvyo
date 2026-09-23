// Package photos stores photos of routes and journeys: re-encoded without
// metadata, in two sizes, on disk.
package photos

import (
	"bytes"
	"errors"
	"image"
	"image/jpeg"
	_ "image/png" // registers the PNG decoder
	"io"
	"math"
	"time"

	"github.com/rwcarlsen/goexif/exif"
	"golang.org/x/image/draw"
	_ "golang.org/x/image/webp" // registers the WebP decoder
)

// Upload limits and stored sizes (long edge in pixels).
const (
	MaxUploadBytes = 20 << 20
	maxPixels      = 60_000_000
	LargePx        = 2048
	ThumbPx        = 480
)

// Errors of Process.
var (
	ErrFormat   = errors.New("photos: not a JPEG, PNG or WebP image")
	ErrTooLarge = errors.New("photos: image too large")
)

// Processed is an upload as we store it: JPEG files without any metadata,
// and what we read from its EXIF data.
type Processed struct {
	Large, Thumb  []byte
	Width, Height int // of Large
	TakenAt       *time.Time
	Lon, Lat      *float64 // where it was taken, if recorded
}

// zurich interprets EXIF times, which have no time zone.
var zurich = func() *time.Location {
	loc, err := time.LoadLocation("Europe/Zurich")
	if err != nil {
		return time.UTC
	}
	return loc
}()

// Process decodes an uploaded image, turns it upright, scales it down and
// re-encodes it, which drops EXIF, XMP and every other metadata.
func Process(r io.Reader) (Processed, error) {
	data, err := io.ReadAll(io.LimitReader(r, MaxUploadBytes+1))
	if err != nil {
		return Processed{}, err
	}
	if len(data) > MaxUploadBytes {
		return Processed{}, ErrTooLarge
	}
	cfg, format, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil {
		return Processed{}, ErrFormat
	}
	if cfg.Width*cfg.Height > maxPixels {
		return Processed{}, ErrTooLarge
	}
	img, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return Processed{}, ErrFormat
	}

	var p Processed
	orientation := 1
	if format == "jpeg" {
		if x, err := exif.Decode(bytes.NewReader(data)); err == nil {
			orientation = readOrientation(x)
			p.TakenAt = readTime(x)
			p.Lon, p.Lat = readPosition(x)
		}
	}

	large := orient(fit(img, LargePx), orientation)
	thumb := fit(large, ThumbPx)
	b := large.Bounds()
	p.Width, p.Height = b.Dx(), b.Dy()
	if p.Large, err = encode(large, 85); err != nil {
		return Processed{}, err
	}
	if p.Thumb, err = encode(thumb, 80); err != nil {
		return Processed{}, err
	}
	return p, nil
}

func encode(img image.Image, quality int) ([]byte, error) {
	var buf bytes.Buffer
	err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: quality})
	return buf.Bytes(), err
}

// fit scales img down so that its long edge is at most px.
func fit(img image.Image, px int) image.Image {
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	if max(w, h) <= px {
		return img
	}
	scale := float64(px) / float64(max(w, h))
	dst := image.NewRGBA(image.Rect(0, 0, max(1, int(math.Round(float64(w)*scale))), max(1, int(math.Round(float64(h)*scale)))))
	draw.CatmullRom.Scale(dst, dst.Bounds(), img, b, draw.Src, nil)
	return dst
}

func readOrientation(x *exif.Exif) int {
	tag, err := x.Get(exif.Orientation)
	if err != nil {
		return 1
	}
	o, err := tag.Int(0)
	if err != nil || o < 1 || o > 8 {
		return 1
	}
	return o
}

func readTime(x *exif.Exif) *time.Time {
	t, err := x.DateTime()
	if err != nil {
		return nil
	}
	// Wall clock time of the camera, taken as Swiss time.
	t = time.Date(t.Year(), t.Month(), t.Day(), t.Hour(), t.Minute(), t.Second(), 0, zurich)
	if t.Year() < 1990 || t.After(time.Now().Add(48*time.Hour)) {
		return nil
	}
	return &t
}

func readPosition(x *exif.Exif) (lon, lat *float64) {
	la, lo, err := x.LatLong()
	if err != nil || math.IsNaN(la) || math.IsNaN(lo) || math.Abs(la) > 90 || math.Abs(lo) > 180 || (la == 0 && lo == 0) {
		return nil, nil
	}
	return &lo, &la
}

// orient turns an image upright according to its EXIF orientation (1–8).
func orient(img image.Image, o int) image.Image {
	if o == 1 {
		return img
	}
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	// Orientations 5–8 swap width and height.
	dw, dh := w, h
	if o >= 5 {
		dw, dh = h, w
	}
	dst := image.NewRGBA(image.Rect(0, 0, dw, dh))
	for y := range h {
		for x := range w {
			var dx, dy int
			switch o {
			case 2: // mirror
				dx, dy = w-1-x, y
			case 3: // rotate 180°
				dx, dy = w-1-x, h-1-y
			case 4: // mirror vertically
				dx, dy = x, h-1-y
			case 5: // transpose
				dx, dy = y, x
			case 6: // rotate 90° clockwise
				dx, dy = h-1-y, x
			case 7: // transverse
				dx, dy = h-1-y, w-1-x
			case 8: // rotate 90° anticlockwise
				dx, dy = y, w-1-x
			}
			dst.Set(dx, dy, img.At(b.Min.X+x, b.Min.Y+y))
		}
	}
	return dst
}
