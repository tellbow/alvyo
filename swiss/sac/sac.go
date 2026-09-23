// Package sac grades hiking routes on the SAC hiking scale (T1–T6).
//
// OpenStreetMap's sac_scale is precise where it exists but is often missing.
// The official Swiss trail category from swissTLM3D (yellow Wanderweg,
// white-red-white Bergwanderweg, white-blue-white Alpinwanderweg) is always
// known on signed trails but only gives a range. A segment's grade combines
// both: the OSM value clamped into the category's range, or the category's
// default when OSM has none.
package sac

// Category is the official Swiss hiking trail category of a segment.
type Category int

// Trail categories as named in swissTLM3D.
const (
	NoCategory Category = iota
	Wanderweg
	Bergwanderweg
	Alpinwanderweg
)

// ParseCategory maps a swissTLM3D "wanderwege" value to a Category.
func ParseCategory(s string) Category {
	switch s {
	case "Wanderweg":
		return Wanderweg
	case "Bergwanderweg":
		return Bergwanderweg
	case "Alpinwanderweg":
		return Alpinwanderweg
	}
	return NoCategory
}

func (c Category) String() string {
	switch c {
	case Wanderweg:
		return "Wanderweg"
	case Bergwanderweg:
		return "Bergwanderweg"
	case Alpinwanderweg:
		return "Alpinwanderweg"
	}
	return "none"
}

// bounds of each category on the SAC scale, and the grade assumed when OSM
// has no sac_scale.
var categoryRange = map[Category]struct{ lo, hi, def, defHi int }{
	Wanderweg:      {1, 2, 1, 2},
	Bergwanderweg:  {2, 4, 2, 3},
	Alpinwanderweg: {4, 6, 4, 6},
}

// Segment is one stretch of a route with the facts known about it.
type Segment struct {
	LengthM  float64
	OSM      int      // OSM sac_scale as T1–T6 (1–6), 0 if unknown
	Category Category // official trail category, NoCategory if off the network
	Path     bool     // a footpath (not a road or track)
}

// Grade is the SAC grade of a segment: T is the most likely value and Max the
// upper end when only a range is known (Max == T when certain).
type Grade struct {
	T, Max int
	// Official is false when the segment is off the official trail network
	// and OSM has no sac_scale, i.e. the grade is a guess.
	Official bool
}

// Of returns the grade of a segment.
func Of(s Segment) Grade {
	r, ok := categoryRange[s.Category]
	switch {
	case ok && s.OSM > 0:
		t := min(max(s.OSM, r.lo), r.hi)
		return Grade{T: t, Max: t, Official: true}
	case ok:
		return Grade{T: r.def, Max: r.defHi, Official: true}
	case s.OSM > 0:
		return Grade{T: s.OSM, Max: s.OSM, Official: true}
	case s.Path:
		return Grade{T: 2, Max: 3}
	default:
		return Grade{T: 1, Max: 1, Official: true} // roads and tracks
	}
}

// Summary grades a whole route.
type Summary struct {
	Grade     int             // hardest segment, T1–T6
	Max       int             // upper end if the hardest part is only known as a range
	Breakdown map[int]float64 // metres per grade
	// UnofficialM is the length graded by guess (off the official network
	// without OSM sac_scale).
	UnofficialM float64
}

// Route summarises the grades of consecutive segments.
func Route(segs []Segment) Summary {
	s := Summary{Breakdown: map[int]float64{}}
	for _, seg := range segs {
		if seg.LengthM <= 0 {
			continue
		}
		g := Of(seg)
		s.Breakdown[g.T] += seg.LengthM
		if !g.Official {
			s.UnofficialM += seg.LengthM
		}
		switch {
		case g.T > s.Grade:
			s.Grade, s.Max = g.T, g.Max
		case g.T == s.Grade:
			s.Max = max(s.Max, g.Max)
		}
	}
	return s
}
