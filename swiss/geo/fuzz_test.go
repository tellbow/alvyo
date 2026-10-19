package geo

import (
	"encoding/binary"
	"math"
	"testing"
)

// FuzzSimplify: the first and last points stay, the rest keep their order,
// and every dropped point lies within the tolerance of the simplified line.
func FuzzSimplify(f *testing.F) {
	f.Add([]byte{0, 0, 10, 10, 20, 0, 30, 10, 40, 0}, 5.0)
	f.Add([]byte{1, 1, 1, 1, 1, 1, 200, 3}, 0.5)
	f.Fuzz(func(t *testing.T, data []byte, tolerance float64) {
		if !(tolerance >= 0 && tolerance <= 1000) {
			t.Skip()
		}
		// Two bytes per point: up to ±1.3 km around Bern in 10 m steps.
		var pts []Point
		for i := 0; i+1 < len(data); i += 2 {
			pts = append(pts, Point{7.44 + float64(int8(data[i]))*1e-4, 46.95 + float64(int8(data[i+1]))*1e-4})
		}
		out := Simplify(pts, tolerance)
		if len(pts) < 3 {
			if len(out) != len(pts) {
				t.Fatalf("%d points became %d", len(pts), len(out))
			}
			return
		}
		if out[0] != pts[0] || out[len(out)-1] != pts[len(pts)-1] {
			t.Fatal("first or last point dropped")
		}
		j := 0
		for _, p := range pts {
			if j < len(out) && p == out[j] {
				j++
			}
		}
		if j != len(out) {
			t.Fatalf("output is not a subsequence of the input: %v", out)
		}
		kx, ky := earthRadius*math.Pi/180*math.Cos(pts[0].Lat*math.Pi/180), earthRadius*math.Pi/180
		xy := func(p Point) [2]float64 { return [2]float64{p.Lon * kx, p.Lat * ky} }
		for i, p := range pts {
			d := math.Inf(1)
			for k := 1; k < len(out); k++ {
				d = min(d, segDistance(xy(p), xy(out[k-1]), xy(out[k])))
			}
			if d > tolerance+1e-6 {
				t.Fatalf("point %d is %.2f m off the simplified line, tolerance %.2f", i, d, tolerance)
			}
		}
	})
}

// FuzzDensify: no segment is longer than the step, and the input points are
// where orig says.
func FuzzDensify(f *testing.F) {
	f.Add([]byte{0, 0, 100, 50, 100, 50, 0, 200}, 25.0)
	f.Fuzz(func(t *testing.T, data []byte, step float64) {
		if !(step >= 1 && step <= 10_000) {
			t.Skip()
		}
		var pts []Point
		for i := 0; i+3 < len(data); i += 4 {
			pts = append(pts, Point{
				7.44 + float64(int16(binary.LittleEndian.Uint16(data[i:])))*1e-5,
				46.95 + float64(int16(binary.LittleEndian.Uint16(data[i+2:])))*1e-5,
			})
		}
		out, orig := Densify(pts, step)
		for i, k := range orig {
			if out[k] != pts[i] {
				t.Fatalf("orig[%d] = %d points at %v, not %v", i, k, out[k], pts[i])
			}
		}
		// Points are evenly spaced in degrees, not on the sphere: over tens of
		// kilometres a piece comes out about 0.1 % longer.
		for i := 1; i < len(out); i++ {
			if d := Distance(out[i-1], out[i]); d > step*1.005 {
				t.Fatalf("segment %d is %.2f m, step %.2f", i, d, step)
			}
		}
	})
}
