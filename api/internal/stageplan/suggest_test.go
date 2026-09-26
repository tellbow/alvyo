package stageplan

import (
	"slices"
	"testing"

	"github.com/tellbow/alvyo/swiss/geo"
)

// testWay is a way along straight lines through pts.
func testWay(name string, pts ...geo.Point) *way {
	line, _ := geo.Densify(pts, 50)
	w := newWay(pts, line)
	w.viaName = name
	return &w
}

func TestPick(t *testing.T) {
	a, b := geo.Point{Lon: 8.0, Lat: 46.5}, geo.Point{Lon: 8.6, Lat: 46.5} // 46 km
	north := func(lat float64) geo.Point { return geo.Point{Lon: 8.3, Lat: lat} }
	direct := testWay("", a, b)
	cands := []*way{
		nil, // no path near its point
		testWay("north", a, north(46.6), b),
		testWay("south", a, north(46.4), b),
		testWay("close by", a, north(46.502), b), // the same way
		testWay("far north", a, north(46.85), b), // 1.8 times as long
		// Up a dead-end valley and back the same way.
		testWay("dead end", a, geo.Point{Lon: 8.3, Lat: 46.5}, north(46.55), geo.Point{Lon: 8.3, Lat: 46.5}, b),
	}
	got := pick(*direct, cands)
	var names []string
	for _, w := range got {
		names = append(names, w.viaName)
	}
	// North and south are as long: either may come first.
	if len(names) != 3 || names[0] != "" || !slices.Contains(names, "north") || !slices.Contains(names, "south") {
		t.Errorf("picked %q, want the direct one, north and south", names)
	}
}

func TestSpurAndOverlap(t *testing.T) {
	a, b := geo.Point{Lon: 8.0, Lat: 46.5}, geo.Point{Lon: 8.2, Lat: 46.5}
	mid := geo.Point{Lon: 8.1, Lat: 46.5}
	up := geo.Point{Lon: 8.1, Lat: 46.55} // 5.5 km up, and back
	if w := testWay("", a, b); spur(w.line) {
		t.Error("a straight line is no dead end")
	}
	if w := testWay("", a, mid, up, mid, b); !spur(w.line) {
		t.Error("up and back the same way is a dead end")
	}
	// Switchbacks: the path comes close to itself only a few hundred
	// metres further on.
	zig := []geo.Point{a}
	for i := 1; i <= 20; i++ {
		lat := 46.5
		if i%2 == 1 {
			lat = 46.5008 // 90 m
		}
		zig = append(zig, geo.Point{Lon: 8.0 + float64(i)*0.0005, Lat: lat})
	}
	if w := testWay("", zig...); spur(w.line) {
		t.Error("switchbacks are no dead end")
	}
	straight, bent := testWay("", a, b), testWay("", a, up, b)
	if got := overlap(straight.line, straight.line); got != 1 {
		t.Errorf("overlap with itself: %.2f", got)
	}
	if got := overlap(bent.line, straight.line); got > 0.2 {
		t.Errorf("overlap of a way 5 km off: %.2f", got)
	}
}

// A night another suggestion has is taken where another fits as well.
func TestSplitFavoursSharedNights(t *testing.T) {
	secs := make([]float64, 101)
	for i := range secs {
		secs[i] = float64(i) * 360 // 10 h
	}
	cands := []Candidate{{Index: 49, Preferred: true}, {Index: 51, Preferred: true, Shared: true}}
	got, err := Split(secs, cands, Days{N: 2})
	if err != nil || len(got) != 1 || got[0] != 1 {
		t.Errorf("ends %v, %v; want the shared one", got, err)
	}
	// Not over a place of the kind asked for.
	cands = []Candidate{{Index: 49, Preferred: true}, {Index: 51, Shared: true}}
	if got, _ := Split(secs, cands, Days{N: 2}); len(got) != 1 || got[0] != 0 {
		t.Errorf("ends %v; want the one of the kind asked for", got)
	}
}
