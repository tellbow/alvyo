package routing

import (
	"context"
	"math"
	"strconv"
	"strings"

	"github.com/tellbow/alvyo/swiss/geo"
)

// Retrail matches a stored leg's line against the official trail network
// again and grades its SAC anew with the categories found: for legs planned
// while the network was missing (or since changed). The line, elevations and
// times stay. It reports whether anything changed.
//
// OSM's sac_scale is not stored with a leg, so it is read back from the
// grades the leg has: off the network a footpath without one was guessed
// T2, a road or track T1, anything else was OSM's value. A footpath graded
// T2 is OSM's T2 only if nothing of the leg was guessed; otherwise it is
// taken as a guess, and on the network gets its category's grade.
func (m *TrailMatcher) Retrail(ctx context.Context, leg Leg) (Leg, bool, error) {
	n := len(leg.Coordinates)
	if n < 2 {
		return leg, false, nil
	}
	oldTrail, ok1 := perSegment(leg.Details.Trail, n-1)
	oldSAC, ok2 := perSegment(leg.Details.SAC, n-1)
	way, ok3 := perSegment(leg.Details.WayType, n-1)
	surface, ok4 := perSegment(leg.Details.Surface, n-1)
	if !ok1 || !ok2 || !ok3 || !ok4 {
		return leg, false, nil // runs that do not fit the line: left as they are
	}

	pts := make([]geo.Point, n)
	for i, c := range leg.Coordinates {
		pts[i] = geo.Point{Lon: c[0], Lat: c[1]}
	}
	trails, err := m.Categories(ctx, pts)
	if err != nil {
		return leg, false, err
	}
	segs := make([]segment, n-1)
	for i := range segs {
		segs[i] = segment{length: geo.Distance(pts[i], pts[i+1]), trail: trails[i]}
	}
	smoothTrails(segs)
	changed := false
	for i, s := range segs {
		if s.trail.String() != oldTrail[i] {
			changed = true
			break
		}
	}
	if !changed {
		return leg, false, nil
	}

	nothingGuessed := leg.SAC.UnofficialM < 1
	// Footpaths graded T2 off the network (only these can have been
	// guessed), and of them those still off it.
	ambiguousM, stayM := 0.0, 0.0
	for i := range segs {
		roadClass := wayRoadClass[way[i]]
		t, _ := strconv.Atoi(strings.TrimPrefix(oldSAC[i], "T"))
		osm := t
		path := isPath(roadClass)
		if oldTrail[i] == "none" && path && t == 2 {
			ambiguousM += segs[i].length
			if segs[i].trail.String() == "none" {
				stayM += segs[i].length
			}
		}
		if oldTrail[i] == "none" && (path && t == 2 && !nothingGuessed || !path && t == 1) {
			osm = 0
		}
		segs[i].osmSAC = osm
		segs[i].roadClass = roadClass
		segs[i].surface = surfaceRaw[surface[i]]
	}
	out := leg
	summarise(&out, segs)
	// Which of them were guessed is not known: cautiously, all of those
	// still off the network, up to what the leg had guessed.
	if !nothingGuessed && ambiguousM > 0 {
		out.SAC.UnofficialM = math.Round(min(leg.SAC.UnofficialM, stayM))
	}
	return out, true, nil
}

// A road class and a surface that wayType and surfaceGroup map back to the
// stored value.
var (
	wayRoadClass = map[string]string{"road": "road", "track": "track", "path": "path", "steps": "steps", "unknown": ""}
	surfaceRaw   = map[string]string{"paved": "paved", "gravel": "gravel", "natural": "ground", "unknown": ""}
)

// perSegment spreads runs over n segments; false when they do not cover
// them in order.
func perSegment(runs []Run, n int) ([]string, bool) {
	out := make([]string, n)
	next := 0
	for _, r := range runs {
		if r.From != next || r.To <= r.From || r.To > n {
			return nil, false
		}
		for k := r.From; k < r.To; k++ {
			out[k] = r.Value
		}
		next = r.To
	}
	return out, next == n
}
