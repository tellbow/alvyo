package stats

import (
	"math"
	"math/rand/v2"
	"testing"
	"time"

	"github.com/tellbow/odysgeh/swiss/geo"
)

// line returns n+1 points going north from (8, 46) with the given spacing.
func line(n int, spacing float64) []geo.Point {
	const mPerDegLat = 111195.08
	pts := make([]geo.Point, n+1)
	for i := range pts {
		pts[i] = geo.Point{Lon: 8, Lat: 46 + float64(i)*spacing/mPerDegLat}
	}
	return pts
}

func TestFlat(t *testing.T) {
	pts := line(100, 42) // 4.2 km
	ele := make([]float64, len(pts))
	s := Compute(pts, ele)
	if math.Abs(s.DistanceM-4200) > 1 {
		t.Errorf("distance %.1f", s.DistanceM)
	}
	if s.AscentM != 0 || s.DescentM != 0 {
		t.Errorf("ascent %v / %v on flat ground", s.AscentM, s.DescentM)
	}
	// 4.2 km at 14.271 min/km.
	if d := s.Duration - minutes(4.2*14.271); d.Abs() > time.Second {
		t.Errorf("duration %v, want 59m56s", s.Duration)
	}
	if s.Duration != s.DurationReverse {
		t.Errorf("flat route should be symmetric: %v vs %v", s.Duration, s.DurationReverse)
	}
}

func TestClimb(t *testing.T) {
	pts := line(50, 20) // 1 km
	ele := make([]float64, len(pts))
	for i := range ele {
		ele[i] = 500 + float64(i)*2 // +100 m over 1 km (10 %)
	}
	s := Compute(pts, ele)
	if math.Abs(s.AscentM-100) > 0.5 || s.DescentM > 0.5 {
		t.Errorf("ascent %.2f descent %.2f", s.AscentM, s.DescentM)
	}
	if s.EleMinM != 500 || s.EleMaxM != 600 {
		t.Errorf("range %v–%v", s.EleMinM, s.EleMaxM)
	}
	// Golden: 10 % over 1 km = 19.99866 min up, 14.20858 min down.
	if d := s.Duration - minutes(19.998660671559996); d.Abs() > time.Second {
		t.Errorf("uphill %v", s.Duration)
	}
	if d := s.DurationReverse - minutes(14.208582088760002); d.Abs() > time.Second {
		t.Errorf("downhill %v", s.DurationReverse)
	}
}

func TestAscentThreshold(t *testing.T) {
	// With a threshold, ±1 m jitter on flat ground does not add up; without
	// one (the default, like the official figures) every metre counts.
	ele := make([]float64, 1000)
	for i := range ele {
		if i%2 == 1 {
			ele[i] = 1
		}
	}
	if up, down := ascent(ele, 3); up > 1 || down > 1 {
		t.Errorf("noise counted: up %.1f down %.1f", up, down)
	}
	if up, down := ascent(ele, AscentThreshold); up != 500 || down != 499 {
		t.Errorf("every climb: up %.1f down %.1f", up, down)
	}
}

func TestAscentHysteresisKeepsPeaks(t *testing.T) {
	// Up to the peak, 3 m back down: with a 3 m threshold the dip does not
	// count, but the climb goes all the way to 12 m.
	for _, tc := range []struct {
		ele            []float64
		threshold      float64
		wantUp, wantDn float64
	}{
		{[]float64{0, 10, 12, 9}, 3, 12, 3},
		{[]float64{0, 10, 12, 9}, 0, 12, 3},
		{[]float64{0, 10, 12, 11, 20}, 3, 20, 0},   // a small dip on the way up
		{[]float64{100, 90, 88, 90, 80}, 3, 0, 20}, // a small rise on the way down
		{[]float64{0, 2, 0, 2, 0, 2}, 3, 2, 0},     // noise within the threshold
		{[]float64{0, 50, 10, 60, 55}, 3, 100, 45}, // two climbs, peaks counted
		{[]float64{5}, 3, 0, 0},
	} {
		up, down := ascent(tc.ele, tc.threshold)
		if math.Abs(up-tc.wantUp) > 1e-9 || math.Abs(down-tc.wantDn) > 1e-9 {
			t.Errorf("%v, threshold %v: up %v down %v, want %v %v", tc.ele, tc.threshold, up, down, tc.wantUp, tc.wantDn)
		}
	}
}

func TestAscentAddsUp(t *testing.T) {
	// Whatever the threshold, up minus down is the end minus the start; with
	// no threshold, up is every rise.
	rng := rand.New(rand.NewPCG(1, 2))
	for range 200 {
		ele := make([]float64, 2+rng.IntN(50))
		for i := range ele {
			ele[i] = rng.Float64() * 30
		}
		rises := 0.0
		for i := 1; i < len(ele); i++ {
			rises += max(ele[i]-ele[i-1], 0)
		}
		for _, th := range []float64{0, 1, 3, 10} {
			up, down := ascent(ele, th)
			if math.Abs(up-down-(ele[len(ele)-1]-ele[0])) > 1e-9 || up < 0 || down < 0 {
				t.Fatalf("%v, threshold %v: up %v down %v", ele, th, up, down)
			}
			if th == 0 && math.Abs(up-rises) > 1e-9 {
				t.Fatalf("%v: up %v, rises %v", ele, up, rises)
			}
		}
	}
}

func TestAscentUpAndDown(t *testing.T) {
	ele := []float64{0, 50, 100, 60, 20, 80}
	up, down := ascent(ele, AscentThreshold)
	if up != 160 || down != 80 {
		t.Errorf("up %v down %v, want 160 / 80", up, down)
	}
}

func TestDegenerate(t *testing.T) {
	if s := Compute(nil, nil); s != (Stats{}) {
		t.Errorf("empty: %+v", s)
	}
	if s := Compute(line(0, 10), []float64{5}); s != (Stats{}) {
		t.Errorf("single point: %+v", s)
	}
}
