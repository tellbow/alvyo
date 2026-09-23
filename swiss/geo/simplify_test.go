package geo

import (
	"math"
	"testing"
)

func TestSimplify(t *testing.T) {
	// A 1 km straight line east with ±2 m of north–south jitter, and one
	// real 50 m detour in the middle.
	const mPerDeg = 111_195.0
	var pts []Point
	for i := 0; i <= 200; i++ {
		jitter := 2 * math.Sin(float64(i)*1.7)
		if i == 100 {
			jitter = 50
		}
		pts = append(pts, Point{Lon: 8 + float64(i)*5/(mPerDeg*math.Cos(46.5*math.Pi/180)), Lat: 46.5 + jitter/mPerDeg})
	}
	out := Simplify(pts, 5)
	if len(out) > 6 {
		t.Errorf("kept %d of %d points", len(out), len(pts))
	}
	if out[0] != pts[0] || out[len(out)-1] != pts[len(pts)-1] {
		t.Error("ends not kept")
	}
	found := false
	for _, p := range out {
		if p == pts[100] {
			found = true
		}
	}
	if !found {
		t.Error("the detour was simplified away")
	}
	if got := Simplify(pts[:2], 5); len(got) != 2 {
		t.Errorf("two points: %v", got)
	}
}
