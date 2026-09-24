package sac

import "testing"

func TestOf(t *testing.T) {
	cases := []struct {
		name string
		seg  Segment
		want Grade
	}{
		{"OSM T3 on Bergwanderweg", Segment{OSM: 3, Category: Bergwanderweg}, Grade{3, 3, true}},
		{"OSM T5 clamped to Bergwanderweg max T4", Segment{OSM: 5, Category: Bergwanderweg}, Grade{4, 4, true}},
		{"OSM T1 clamped up to Bergwanderweg min T2", Segment{OSM: 1, Category: Bergwanderweg}, Grade{2, 2, true}},
		{"OSM T2 on Wanderweg", Segment{OSM: 2, Category: Wanderweg}, Grade{2, 2, true}},
		{"Bergwanderweg without OSM", Segment{Category: Bergwanderweg}, Grade{2, 3, true}},
		{"Wanderweg without OSM", Segment{Category: Wanderweg}, Grade{1, 2, true}},
		{"Alpinwanderweg without OSM", Segment{Category: Alpinwanderweg}, Grade{4, 6, true}},
		{"OSM T4 off network", Segment{OSM: 4}, Grade{4, 4, true}},
		{"unknown path off network", Segment{Path: true}, Grade{2, 3, false}},
		{"road or track", Segment{}, Grade{1, 1, true}},
	}
	for _, c := range cases {
		if got := Of(c.seg); got != c.want {
			t.Errorf("%s: got %+v, want %+v", c.name, got, c.want)
		}
	}
}

func TestRoute(t *testing.T) {
	s := Route([]Segment{
		{LengthM: 1000},                         // road: T1
		{LengthM: 3000, Category: Wanderweg},    // T1 (–T2)
		{LengthM: 800, Category: Bergwanderweg}, // T2–T3
		{LengthM: 200, OSM: 2, Category: Bergwanderweg},
		{LengthM: 50, Path: true}, // guessed T2
		{LengthM: 0, OSM: 6},      // zero length ignored
	})
	if s.Grade != 2 || s.Max != 3 {
		t.Errorf("grade T%d–T%d, want T2–T3", s.Grade, s.Max)
	}
	if s.Breakdown[1] != 4000 || s.Breakdown[2] != 1050 {
		t.Errorf("breakdown %v", s.Breakdown)
	}
	if s.UnofficialM != 50 {
		t.Errorf("unofficial %v", s.UnofficialM)
	}

	// A certain T3 segment makes the route T3 regardless of ranges below.
	s = Route([]Segment{{LengthM: 100, Category: Bergwanderweg}, {LengthM: 100, OSM: 3, Category: Bergwanderweg}})
	if s.Grade != 3 || s.Max != 3 {
		t.Errorf("grade T%d–T%d, want T3", s.Grade, s.Max)
	}

	// But a guessed part may be harder than the hardest certain one.
	s = Route([]Segment{{LengthM: 100, OSM: 5, Category: Alpinwanderweg}, {LengthM: 100, Category: Alpinwanderweg}})
	if s.Grade != 5 || s.Max != 6 {
		t.Errorf("grade T%d–T%d, want T5–T6", s.Grade, s.Max)
	}
}

func TestParseCategory(t *testing.T) {
	for _, c := range []Category{Wanderweg, Bergwanderweg, Alpinwanderweg} {
		if ParseCategory(c.String()) != c {
			t.Errorf("round trip %v", c)
		}
	}
	if ParseCategory("") != NoCategory || ParseCategory("other") != NoCategory {
		t.Error("unknown values must map to NoCategory")
	}
}
