package routes

import (
	"math"
	"testing"
	"time"

	"github.com/tellbow/alvyo/api/internal/routing"
)

func TestForOthers(t *testing.T) {
	// Three legs of 10 segments of 38 m (0.0005° at 46.5° N): 1150 m.
	legs := []routing.Leg{leg(8.0, 10), leg(8.005, 10), leg(8.010, 10)}
	legs[1].Details.SAC = []routing.Run{{From: 0, To: 5, Value: "T2"}, {From: 5, To: 10, Value: "T4"}}
	c := content(legs...)
	c.Anchors[0].Name = "Zuhause"
	r := Route{Anchors: c.Anchors, Legs: c.Legs}

	if got := r.ForOthers(); len(got.Legs) != 3 {
		t.Fatalf("a planned route is shown whole: %d legs", len(got.Legs))
	}

	r.Hike = &Hike{At: time.Now()}
	got := r.ForOthers()
	// From the first point more than 500 m from the start (8.007, vertex 4
	// of leg 2) to the last more than 500 m from the end (8.008).
	if len(got.Legs) != 1 {
		t.Fatalf("legs: %d", len(got.Legs))
	}
	l := got.Legs[0]
	if len(l.Coordinates) != 3 || math.Abs(l.Coordinates[0][0]-8.007) > 1e-9 {
		t.Errorf("coordinates: %v", l.Coordinates)
	}
	if want := []routing.Run{{From: 0, To: 1, Value: "T2"}, {From: 1, To: 2, Value: "T4"}}; len(l.Details.SAC) != 2 ||
		l.Details.SAC[0] != want[0] || l.Details.SAC[1] != want[1] {
		t.Errorf("SAC runs: %v", l.Details.SAC)
	}
	if l.DistanceM < 75 || l.DistanceM > 78 || l.SAC.Grade != 4 || l.SAC.Breakdown["T2"] < 30 {
		t.Errorf("numbers not recomputed: %.0f m, T%d, %v", l.DistanceM, l.SAC.Grade, l.SAC.Breakdown)
	}
	if len(got.Anchors) != 2 || got.Anchors[0].Name != "" || got.Anchors[0].Lon != l.Coordinates[0][0] {
		t.Errorf("anchors: %+v", got.Anchors)
	}
	if len(r.Legs) != 3 || len(r.Legs[1].Coordinates) != 11 {
		t.Error("the stored route changed")
	}

	// A loop: start and end at the same place, both hidden.
	back := leg(8.0, 20)
	for i := range back.Coordinates {
		back.Coordinates[i][0] = 8.0 + float64(20-i)*0.0005
	}
	loop := content(leg(8.0, 20), back)
	r = Route{Anchors: loop.Anchors, Legs: loop.Legs, Summary: Summary{Hike: &Hike{}}}
	got = r.ForOthers()
	if len(got.Legs) != 2 || got.Legs[0].Coordinates[0][0] < 8.0065 || got.Legs[1].Coordinates[len(got.Legs[1].Coordinates)-1][0] < 8.0065 {
		t.Errorf("loop: %+v", got.Anchors)
	}
}
