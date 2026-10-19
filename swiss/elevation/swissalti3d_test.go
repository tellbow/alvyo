package elevation

import (
	"context"
	"errors"
	"fmt"
	"image"
	"image/png"
	"math"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/tellbow/alvyo/swiss/geo"
	"github.com/tellbow/alvyo/swiss/lv95"
)

// writeTiles writes the swissALTI3D tiles around pts with heights from
// terrain at the pixels' centres, as infra/data-import/swissalti3d.py does;
// skip leaves a tile out.
func writeTiles(t *testing.T, dir string, pts []geo.Point, terrain func(e, n float64) *float64, skip ...string) {
	t.Helper()
	keys := map[[2]int]bool{}
	for _, p := range pts {
		e, n := lv95.FromWGS84(p.Lon, p.Lat)
		for _, d := range [][2]float64{{-3, -3}, {3, -3}, {-3, 3}, {3, 3}} {
			keys[[2]int{int(e+d[0]) / 1000, int(n+d[1]) / 1000}] = true
		}
	}
	for k := range keys {
		name := fmt.Sprintf("%d-%d", k[0], k[1])
		if slices.Contains(skip, name) {
			continue
		}
		img := image.NewGray16(image.Rect(0, 0, tilePixels, tilePixels))
		for row := range tilePixels {
			for col := range tilePixels {
				e := float64(k[0]*1000 + 2*col + 1)
				n := float64(k[1]*1000 + 1000 - 2*row - 1)
				dm := uint16(math.Round(*terrain(e, n) * 10))
				img.Pix[2*(row*tilePixels+col)], img.Pix[2*(row*tilePixels+col)+1] = byte(dm>>8), byte(dm)
			}
		}
		f, err := os.Create(filepath.Join(dir, name+".png"))
		if err != nil {
			t.Fatal(err)
		}
		if err := png.Encode(f, img); err != nil {
			t.Fatal(err)
		}
		_ = f.Close()
	}
}

// tileOf is the name of the tile a point lies in.
func tileOf(p geo.Point) string {
	e, n := lv95.FromWGS84(p.Lon, p.Lat)
	return fmt.Sprintf("%d-%d", int(e)/1000, int(n)/1000)
}

func TestSwissALTI3D(t *testing.T) {
	dir := t.TempDir()
	pts := line(20) // about 1.5 km, across tile edges
	writeTiles(t, dir, pts, slope)
	s := &SwissALTI3D{Dir: dir}

	h, err := s.Sample(context.Background(), pts)
	if err != nil {
		t.Fatal(err)
	}
	for i, p := range pts {
		if math.Abs(h[i]-expected(p)) > 0.05 {
			t.Errorf("point %d: %.2f, want %.2f", i, h[i], expected(p))
		}
	}
	if tileOf(pts[0]) == tileOf(pts[len(pts)-1]) {
		t.Error("the line stays in one tile")
	}
}

func TestSwissALTI3DGapIsNoCoverage(t *testing.T) {
	dir := t.TempDir()
	pts := line(40) // three tiles eastwards; the middle one is missing
	gap := tileOf(pts[20])
	if tileOf(pts[0]) == gap || tileOf(pts[len(pts)-1]) == gap {
		t.Fatal("the gap is not in the middle")
	}
	writeTiles(t, dir, pts, slope, gap)
	s := &SwissALTI3D{Dir: dir}

	// Bridged, a line abroad would lose its hills: geo.admin answers it.
	if _, err := s.Sample(context.Background(), pts); !errors.Is(err, ErrNoCoverage) {
		t.Fatalf("err = %v, want ErrNoCoverage", err)
	}
	if _, err := s.Sample(context.Background(), pts[:5]); err != nil {
		t.Fatalf("the part with tiles: %v", err)
	}
}

func TestSwissALTI3DNoCoverage(t *testing.T) {
	s := &SwissALTI3D{Dir: t.TempDir()}
	if _, err := s.Sample(context.Background(), line(3)); !errors.Is(err, ErrNoCoverage) {
		t.Fatalf("err = %v, want ErrNoCoverage", err)
	}
}

func TestSwissALTI3DBrokenTile(t *testing.T) {
	dir := t.TempDir()
	pts := line(3)
	if err := os.WriteFile(filepath.Join(dir, tileOf(pts[0])+".png"), []byte("not a png"), 0o644); err != nil {
		t.Fatal(err)
	}
	s := &SwissALTI3D{Dir: dir}
	if _, err := s.Sample(context.Background(), pts); err == nil || errors.Is(err, ErrNoCoverage) {
		t.Fatalf("err = %v, want a decoding error", err)
	}
}
