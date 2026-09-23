package geo

import (
	"math"
	"math/rand/v2"
	"slices"
	"testing"
)

func near(a, b, tol float64) bool { return math.Abs(a-b) <= tol }

func TestDistance(t *testing.T) {
	// One degree of latitude on the mean-radius sphere.
	if d := Distance(Point{0, 0}, Point{0, 1}); !near(d, 111195.08, 0.1) {
		t.Errorf("1° latitude = %.2f m", d)
	}
	// Bern (Zytglogge) to Zürich HB: ~95.5 km great-circle.
	if d := Distance(Point{7.44795, 46.94799}, Point{8.54021, 47.37818}); !near(d, 95_500, 500) {
		t.Errorf("Bern–Zürich = %.0f m", d)
	}
	if d := Distance(Point{8, 46}, Point{8, 46}); d != 0 {
		t.Errorf("zero distance = %v", d)
	}
}

func TestCumulativeDistance(t *testing.T) {
	pts := []Point{{8, 46}, {8, 46.001}, {8, 46.003}}
	d := CumulativeDistance(pts)
	if d[0] != 0 || !near(d[2], Distance(pts[0], pts[2]), 1e-6) || d[1] >= d[2] {
		t.Errorf("cumulative = %v", d)
	}
}

func TestDensify(t *testing.T) {
	pts := []Point{{8, 46}, {8.001, 46}, {8.001, 46}, {8.01, 46.005}}
	out, orig := Densify(pts, 20)
	for i := 1; i < len(out); i++ {
		if d := Distance(out[i-1], out[i]); d > 20+1e-9 {
			t.Fatalf("segment %d is %.2f m", i, d)
		}
	}
	for i, j := range orig {
		if out[j] != pts[i] {
			t.Errorf("orig[%d]=%d points to %v, want %v", i, j, out[j], pts[i])
		}
	}
	if !slices.IsSorted(orig) {
		t.Errorf("orig not sorted: %v", orig)
	}
	// Total length is preserved (points lie on the segments).
	if a, b := CumulativeDistance(pts), CumulativeDistance(out); !near(a[len(a)-1], b[len(b)-1], 0.01) {
		t.Errorf("length changed: %.3f → %.3f", a[len(a)-1], b[len(b)-1])
	}
	if out, orig := Densify(nil, 20); out != nil || len(orig) != 0 {
		t.Errorf("empty input: %v %v", out, orig)
	}
}

func TestInterpolate(t *testing.T) {
	xs := []float64{0, 10, 10, 30}
	ys := []float64{100, 200, 250, 150}
	got := Interpolate(xs, ys, []float64{-5, 0, 5, 10, 20, 30, 99})
	want := []float64{100, 100, 150, 200, 200, 150, 150}
	for i := range want {
		if !near(got[i], want[i], 1e-9) {
			t.Errorf("at[%d]: got %v, want %v", i, got[i], want[i])
		}
	}
}

func TestResample(t *testing.T) {
	xs := []float64{0, 100, 250}
	ys := []float64{0, 10, 25} // linear: y = x/10
	rx, ry := Resample(xs, ys, 30)
	if rx[0] != 0 || rx[len(rx)-1] != 250 {
		t.Fatalf("endpoints: %v", rx)
	}
	for i := range rx {
		if !near(ry[i], rx[i]/10, 1e-9) {
			t.Errorf("y(%v)=%v", rx[i], ry[i])
		}
		if i > 0 && rx[i]-rx[i-1] > 30+1e-9 {
			t.Errorf("step %v", rx[i]-rx[i-1])
		}
	}
}

func TestLTTB(t *testing.T) {
	rng := rand.New(rand.NewPCG(3, 4))
	xs := make([]float64, 5000)
	ys := make([]float64, 5000)
	for i := range xs {
		xs[i] = float64(i) * 10
		ys[i] = 1000 + 500*math.Sin(float64(i)/300) + rng.Float64()*40
	}
	ys[1234] = 3000 // lone summit spike
	ys[4321] = -50  // lone low point

	idx := LTTB(xs, ys, 300)
	if len(idx) > 300 {
		t.Fatalf("got %d points, want ≤ 300", len(idx))
	}
	if idx[0] != 0 || idx[len(idx)-1] != len(xs)-1 {
		t.Errorf("first/last not kept: %d … %d", idx[0], idx[len(idx)-1])
	}
	if !slices.IsSorted(idx) || len(slices.Compact(slices.Clone(idx))) != len(idx) {
		t.Errorf("indices not strictly increasing")
	}
	if !slices.Contains(idx, 1234) || !slices.Contains(idx, 4321) {
		t.Errorf("extremes dropped")
	}
	if got := LTTB(xs[:10], ys[:10], 300); len(got) != 10 {
		t.Errorf("short series: %d", len(got))
	}
}
