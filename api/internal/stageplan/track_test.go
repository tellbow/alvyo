package stageplan

import (
	"math"
	"testing"

	"github.com/tellbow/alvyo/api/internal/routes"
	"github.com/tellbow/alvyo/api/internal/routing"
)

// testLeg runs east from lon0 at 46.5° N and ele0 metres, n vertices
// 0.0002° (about 15 m) apart, climbing 2 m each, with the SAC grade on all
// of it.
func testLeg(lon0, ele0 float64, n int, sac string) routing.Leg {
	l := routing.Leg{SAC: routing.SACSummary{Max: 3}, Warnings: []string{}}
	for i := range n {
		l.Coordinates = append(l.Coordinates, [3]float64{lon0 + float64(i)*0.0002, 46.5, ele0 + float64(i)*2})
	}
	run := func(v string) []routing.Run { return []routing.Run{{From: 0, To: n - 1, Value: v}} }
	l.Details = routing.Details{SAC: run(sac), Surface: run("natural"), WayType: run("path"), Trail: run("Bergwanderweg")}
	return l
}

// content makes route content of legs, anchors at their ends.
func content(legs []routing.Leg) routes.Content {
	c := routes.Content{Profile: "hike", Legs: legs}
	for _, l := range legs {
		c.Anchors = append(c.Anchors, routes.Anchor{Lon: l.Coordinates[0][0], Lat: l.Coordinates[0][1]})
	}
	last := legs[len(legs)-1].Coordinates
	end := last[len(last)-1]
	c.Anchors = append(c.Anchors, routes.Anchor{Lon: end[0], Lat: end[1]})
	return c
}

func TestTrack(t *testing.T) {
	a := testLeg(8.0, 1000, 51, "T2")
	b := testLeg(8.01, 1100, 51, "T3") // starts where a ends
	_, whole, err := routes.Check(content([]routing.Leg{a, b}))
	if err != nil {
		t.Fatal(err)
	}
	tr := FromLegs([]routing.Leg{a, b})
	if len(tr.Coords) != 101 {
		t.Fatalf("%d vertices, want 101 (the joint once)", len(tr.Coords))
	}

	// Hiking time along the track ends at the route's.
	secs := tr.Seconds()
	if d := math.Abs(secs[len(secs)-1] - float64(whole.DurationS)); d > 30 {
		t.Errorf("hiking time %.0f s, route %d s", secs[len(secs)-1], whole.DurationS)
	}
	for i := 1; i < len(secs); i++ {
		if secs[i] < secs[i-1] {
			t.Fatalf("time goes back at %d", i)
		}
	}

	// Cut in two stages across the joint, legs of about 300 m.
	first, second := tr.Legs(0, 70, 300), tr.Legs(70, 100, 300)
	if len(first) != 4 { // 1050 m: 300, 300, 300, 150
		t.Errorf("%d legs in the first stage", len(first))
	}
	l1, t1, err := routes.Check(content(first))
	if err != nil {
		t.Fatal(err)
	}
	_, t2, err := routes.Check(content(second))
	if err != nil {
		t.Fatal(err)
	}
	if d := math.Abs(t1.DistanceM + t2.DistanceM - whole.DistanceM); d > 1 {
		t.Errorf("stages %.0f + %.0f m, whole %.0f m", t1.DistanceM, t2.DistanceM, whole.DistanceM)
	}
	// The grades follow the cut: T2, then T3 from vertex 50 on.
	if t1.SACGrade != 3 || t2.SACGrade != 3 || l1[0].SAC.Grade != 2 {
		t.Errorf("grades: stage 1 T%d (first leg T%d), stage 2 T%d", t1.SACGrade, l1[0].SAC.Grade, t2.SACGrade)
	}
}
