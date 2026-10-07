package peaks

import (
	"bytes"
	"context"
	"image"
	"image/color"
	"testing"
)

// flat returns tiles each of one height: 1000 + 10·x + y metres; calls
// counts the fetches.
func flat(heights map[[2]int]int, calls *int) TileFunc {
	return func(_ context.Context, x, y int) (image.Image, error) {
		*calls++
		h := 1000 + 10*x + y
		heights[[2]int{x, y}] = h
		v := h + 32768
		img := image.NewNRGBA(image.Rect(0, 0, tileSize, tileSize))
		c := color.NRGBA{R: uint8(v >> 8), G: uint8(v), B: 0, A: 255}
		for i := 0; i < len(img.Pix); i += 4 {
			img.Pix[i], img.Pix[i+1], img.Pix[i+2], img.Pix[i+3] = c.R, c.G, c.B, c.A
		}
		return img, nil
	}
}

func TestPackRoundTrip(t *testing.T) {
	heights, calls := map[[2]int]int{}, 0
	peaks := []Peak{{"Jungfrau", 4158, 7.9625, 46.5367}, {"Piz Palü", 3900, 9.9592, 46.3781}}
	var buf bytes.Buffer
	if err := Write(context.Background(), &buf, flat(heights, &calls), peaks); err != nil {
		t.Fatal(err)
	}
	p, err := Read(&buf)
	if err != nil {
		t.Fatal(err)
	}
	if p.Version != Version || p.Cols != Cols || p.Rows != Rows || p.West != West || p.CellLat != CellLat {
		t.Fatalf("header %+v", p)
	}
	// Every point has the height of its tile, also after the differences.
	for _, pt := range [][2]float64{{7.9625, 46.5367}, {5.01, 48.39}, {11.49, 45.21}, {8.5, 47.0}} {
		tx, ty, _, _ := pixel(pt[0], pt[1])
		if got, want := int(p.Height(pt[0], pt[1])), heights[[2]int{tx, ty}]; got != want {
			t.Errorf("height at %v: %d, want %d", pt, got, want)
		}
	}
	if len(p.Peaks) != 2 || p.Peaks[1].Name != "Piz Palü" || p.Peaks[0].Ele != 4158 ||
		p.Peaks[0].Lon < 7.9624 || p.Peaks[0].Lon > 7.9626 {
		t.Errorf("peaks %+v", p.Peaks)
	}
	// Each tile once, one row of tiles kept at a time.
	if calls != len(heights) || calls > 90 {
		t.Errorf("%d fetches of %d tiles", calls, len(heights))
	}
}
