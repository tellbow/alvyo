// Package phototest makes test images with EXIF data.
package phototest

import (
	"bytes"
	"encoding/binary"
	"image"
	"image/color"
	"image/jpeg"
	"math"
)

// EXIF is what to write into the test image; zero values are left out.
type EXIF struct {
	Orientation int
	DateTime    string // "2006:01:02 15:04:05"
	Lon, Lat    float64
}

// JPEG returns a w×h JPEG whose top left quarter is red (to check
// orientation) with the given EXIF data.
func JPEG(w, h int, x EXIF) []byte {
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := range h {
		for xx := range w {
			c := color.RGBA{0, 0, 255, 255}
			if xx < w/2 && y < h/2 {
				c = color.RGBA{255, 0, 0, 255}
			}
			img.Set(xx, y, c)
		}
	}
	var buf bytes.Buffer
	_ = jpeg.Encode(&buf, img, &jpeg.Options{Quality: 90})
	b := buf.Bytes()
	app1 := exifSegment(x)
	if app1 == nil {
		return b
	}
	return append(append(append([]byte{}, b[:2]...), app1...), b[2:]...) // after SOI
}

type entry struct {
	tag, typ uint16
	count    uint32
	value    []byte // inline if ≤ 4 bytes, else stored in the data area
}

func rational(v float64) []byte {
	deg := math.Floor(v)
	minutes := math.Floor((v - deg) * 60)
	sec := ((v-deg)*60 - minutes) * 60
	out := make([]byte, 24)
	for i, n := range []uint32{uint32(deg), 1, uint32(minutes), 1, uint32(math.Round(sec * 1000)), 1000} {
		binary.LittleEndian.PutUint32(out[i*4:], n)
	}
	return out
}

func short(v int) []byte {
	b := make([]byte, 2)
	binary.LittleEndian.PutUint16(b, uint16(v))
	return b
}

// exifSegment builds an APP1 segment with a little-endian TIFF structure:
// IFD0 (orientation, date, GPS pointer) and a GPS IFD.
func exifSegment(x EXIF) []byte {
	var ifd0, gps []entry
	if x.Orientation != 0 {
		ifd0 = append(ifd0, entry{0x0112, 3, 1, short(x.Orientation)})
	}
	if x.DateTime != "" {
		ifd0 = append(ifd0, entry{0x0132, 2, 20, append([]byte(x.DateTime), 0)})
	}
	if x.Lat != 0 || x.Lon != 0 {
		ns, ew := "N", "E"
		if x.Lat < 0 {
			ns = "S"
		}
		if x.Lon < 0 {
			ew = "W"
		}
		gps = []entry{
			{0x0001, 2, 2, []byte(ns + "\x00")},
			{0x0002, 5, 3, rational(math.Abs(x.Lat))},
			{0x0003, 2, 2, []byte(ew + "\x00")},
			{0x0004, 5, 3, rational(math.Abs(x.Lon))},
		}
		ifd0 = append(ifd0, entry{0x8825, 4, 1, nil}) // offset set below
	}
	if len(ifd0) == 0 {
		return nil
	}
	ifdSize := func(n int) int { return 2 + 12*n + 4 }
	ifd0At := 8
	gpsAt := ifd0At + ifdSize(len(ifd0))
	dataAt := gpsAt
	if len(gps) > 0 {
		dataAt += ifdSize(len(gps))
	}
	var data []byte
	le := binary.LittleEndian
	write := func(out *bytes.Buffer, es []entry) {
		_ = binary.Write(out, le, uint16(len(es)))
		for _, e := range es {
			_ = binary.Write(out, le, e.tag)
			_ = binary.Write(out, le, e.typ)
			_ = binary.Write(out, le, e.count)
			v := make([]byte, 4)
			switch {
			case e.tag == 0x8825:
				le.PutUint32(v, uint32(gpsAt))
			case len(e.value) <= 4:
				copy(v, e.value)
			default:
				le.PutUint32(v, uint32(dataAt+len(data)))
				data = append(data, e.value...)
			}
			out.Write(v)
		}
		_ = binary.Write(out, le, uint32(0))
	}
	var tiff bytes.Buffer
	tiff.WriteString("II")
	_ = binary.Write(&tiff, le, uint16(42))
	_ = binary.Write(&tiff, le, uint32(ifd0At))
	write(&tiff, ifd0)
	if len(gps) > 0 {
		write(&tiff, gps)
	}
	tiff.Write(data)

	payload := append([]byte("Exif\x00\x00"), tiff.Bytes()...)
	seg := []byte{0xFF, 0xE1, 0, 0}
	binary.BigEndian.PutUint16(seg[2:], uint16(len(payload)+2))
	return append(seg, payload...)
}
