package hikingtime

import (
	"math"
	"testing"
)

// Golden values produced by running the original JavaScript loop from
// geoadmin/mf-geoadmin3 ProfileService.js (unrounded) on the same profiles.
var golden = []struct {
	name      string
	dist, ele []float64
	fwd, rev  float64
}{
	{"flat 1 km", []float64{0, 1000}, []float64{500, 500}, 14.271, 14.271},
	{"+10% 1 km", []float64{0, 1000}, []float64{500, 600}, 19.998660671559996, 14.208582088760002},
	{"-10% 1 km", []float64{0, 1000}, []float64{600, 500}, 14.208582088760002, 19.998660671559996},
	{"+30% 500 m", []float64{0, 500}, []float64{500, 650}, 24.397023585419948, 13.760601181620025},
	{"+50% 200 m (linear branch)", []float64{0, 200}, []float64{500, 600}, 17, 9},
	{"-50% 200 m (linear branch)", []float64{0, 200}, []float64{600, 500}, 9, 17},
	{"s = 4 exactly", []float64{0, 100}, []float64{0, 40}, 6.8, 3.6},
	{"duplicate point", []float64{0, 0, 500}, []float64{400, 400, 450}, 9.999330335779998, 7.104291044380001},
}

func TestGolden(t *testing.T) {
	for _, g := range golden {
		if got := Minutes(g.dist, g.ele); math.Abs(got-g.fwd) > 1e-9 {
			t.Errorf("%s forward: got %.12f, want %.12f", g.name, got, g.fwd)
		}
		if got := MinutesReverse(g.dist, g.ele); math.Abs(got-g.rev) > 1e-9 {
			t.Errorf("%s reverse: got %.12f, want %.12f", g.name, got, g.rev)
		}
	}
}

func TestGoldenMountain(t *testing.T) {
	// 12 km, ~1000 m up and down with small undulations, 10 m samples.
	var dist, ele []float64
	for k := 0; k <= 1200; k++ {
		x := float64(k * 10)
		dist = append(dist, x)
		ele = append(ele, 800+1000*math.Sin(math.Pi*x/12000)+30*math.Sin(x/150))
	}
	if got := Minutes(dist, ele); math.Abs(got-338.33480739375005) > 1e-6 {
		t.Errorf("forward: got %.9f", got)
	}
	if got := MinutesReverse(dist, ele); math.Abs(got-340.9305155380101) > 1e-6 {
		t.Errorf("reverse: got %.9f", got)
	}
}

func TestFlatSpeed(t *testing.T) {
	if kmh := 60 / MinutesPerKm(0); math.Abs(kmh-4.2) > 0.01 {
		t.Errorf("flat speed %.3f km/h, want 4.2", kmh)
	}
}

func TestContinuityAtBranchEdges(t *testing.T) {
	// The polynomial and the linear branches should roughly meet at ±4.
	for _, s := range []float64{4, -4} {
		poly := MinutesPerKm(s * 0.999999)
		lin := MinutesPerKm(s)
		if math.Abs(poly-lin)/lin > 0.1 {
			t.Errorf("jump at s=%v: polynomial %.2f vs linear %.2f", s, poly, lin)
		}
	}
}
