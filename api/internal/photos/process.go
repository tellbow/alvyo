// Package photos stores photos of routes and journeys: re-encoded without
// metadata, in two sizes, on disk.
package photos

import (
	"bytes"
	"encoding/binary"
	"errors"
	"image"
	"image/jpeg"
	_ "image/png" // registers the PNG decoder
	"io"
	"math"
	"time"

	"github.com/gen2brain/heic" // registers the HEIC decoder
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
	ErrFormat   = errors.New("photos: not a JPEG, PNG, WebP or HEIC image")
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
	if format == "heic" {
		// Decoded upright already; the EXIF gives when and where.
		if x, err := heic.DecodeExif(bytes.NewReader(data)); err == nil {
			p.TakenAt, p.Lon, p.Lat = heicMeta(x)
		}
	}
	if format == "jpeg" {
		if tiff := exifTIFF(data); tiff != nil && saneTIFF(tiff) {
			if x, err := exif.Decode(bytes.NewReader(tiff)); err == nil {
				orientation = readOrientation(x)
				p.TakenAt = readTime(x)
				p.Lon, p.Lat = readPosition(x)
			}
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
	return wallClock(t)
}

// wallClock takes the camera's time as Swiss time, if it is plausible.
func wallClock(t time.Time) *time.Time {
	t = time.Date(t.Year(), t.Month(), t.Day(), t.Hour(), t.Minute(), t.Second(), 0, zurich)
	if t.Year() < 1990 || t.After(time.Now().Add(48*time.Hour)) {
		return nil
	}
	return &t
}

// heicMeta reads when and where a HEIC photo was taken.
func heicMeta(x *heic.Exif) (at *time.Time, lon, lat *float64) {
	for _, s := range []string{x.DateTimeOriginal, x.DateTime} {
		if t, err := time.Parse("2006:01:02 15:04:05", s); err == nil {
			at = wallClock(t)
			break
		}
	}
	la, lo := x.GPSLatitude, x.GPSLongitude
	if !math.IsNaN(la) && !math.IsNaN(lo) && math.Abs(la) <= 90 && math.Abs(lo) <= 180 && (la != 0 || lo != 0) {
		lon, lat = &lo, &la
	}
	return at, lon, lat
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

// exifTIFF returns the EXIF data (TIFF) of a JPEG, from its APP1 segment.
func exifTIFF(jpg []byte) []byte {
	if len(jpg) < 4 || jpg[0] != 0xFF || jpg[1] != 0xD8 {
		return nil
	}
	for i := 2; i+4 <= len(jpg) && jpg[i] == 0xFF; {
		marker, n := jpg[i+1], int(binary.BigEndian.Uint16(jpg[i+2:]))
		if marker == 0xDA || n < 2 || i+2+n > len(jpg) { // image data, or broken
			return nil
		}
		if seg := jpg[i+4 : i+2+n]; marker == 0xE1 && bytes.HasPrefix(seg, []byte("Exif\x00\x00")) {
			return seg[6:]
		}
		i += 2 + n
	}
	return nil
}

// tiffTypeSize is the size of one value of each TIFF field type.
var tiffTypeSize = map[uint16]uint64{1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8}

// saneTIFF reports whether EXIF data may go to goexif, which believes the
// value counts of its entries: a crafted count makes it allocate gigabytes.
// Every entry's value must fit in the data; the directories goexif reads
// (IFD0 and the ones after it, Exif, GPS, interoperability) are checked.
func saneTIFF(t []byte) bool {
	if len(t) < 8 {
		return false
	}
	var order binary.ByteOrder
	switch string(t[:2]) {
	case "II":
		order = binary.LittleEndian
	case "MM":
		order = binary.BigEndian
	default:
		return false
	}
	size := uint64(len(t))
	todo, seen := []uint32{order.Uint32(t[4:])}, map[uint32]bool{}
	for len(todo) > 0 {
		off := todo[0]
		todo = todo[1:]
		if seen[off] {
			continue
		}
		seen[off] = true
		if uint64(off)+2 > size {
			return false
		}
		n := uint64(order.Uint16(t[off:]))
		end := uint64(off) + 2 + 12*n
		if end+4 > size {
			return false
		}
		for e := uint64(off) + 2; e < end; e += 12 {
			id, typ, count := order.Uint16(t[e:]), order.Uint16(t[e+2:]), order.Uint32(t[e+4:])
			if tiffTypeSize[typ]*uint64(count) > size {
				return false
			}
			if id == 0x8769 || id == 0x8825 || id == 0xA005 { // Exif, GPS, interoperability
				todo = append(todo, order.Uint32(t[e+8:]))
			}
		}
		if next := order.Uint32(t[end:]); next != 0 {
			todo = append(todo, next)
		}
	}
	return true
}
