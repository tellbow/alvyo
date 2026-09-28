package routes

import (
	"github.com/tellbow/alvyo/api/internal/routing"
	"github.com/tellbow/alvyo/swiss/geo"
)

// PrivacyM is how far around a recorded hike's start and end others see
// nothing of it: that is usually where the hiker lives or stayed. The SQL
// function shown_line does the same for lists and maps.
const PrivacyM = 500.0

// ForOthers returns the route as others than its owner and editors see it:
// a recorded hike from the first point more than PrivacyM from its start
// to the last point more than PrivacyM from its end, with the legs' numbers
// recomputed; without legs and anchors when nothing is left. Other routes
// are returned unchanged. The totals stay those of the hike.
func (r Route) ForOthers() Route {
	if r.Hike == nil || len(r.Legs) == 0 {
		return r
	}
	var flat [][3]float64
	for _, l := range r.Legs {
		flat = append(flat, l.Coordinates...)
	}
	pt := func(c [3]float64) geo.Point { return geo.Point{Lon: c[0], Lat: c[1]} }
	start, end := pt(flat[0]), pt(flat[len(flat)-1])
	r.Hidden = []geo.Point{start, end}
	lo, hi := -1, -1
	for i, c := range flat {
		if lo < 0 && geo.Distance(start, pt(c)) > PrivacyM {
			lo = i
		}
		if geo.Distance(end, pt(c)) > PrivacyM {
			hi = i
		}
	}
	legs, anchors := r.Legs, r.Anchors
	r.Legs, r.Anchors = []routing.Leg{}, []Anchor{}
	if lo < 0 || hi <= lo {
		return r
	}

	off := 0
	for i, l := range legs {
		n := len(l.Coordinates)
		a, b := max(lo-off, 0), min(hi-off, n-1)
		off += n
		if b-a < 1 {
			continue
		}
		cut := l
		cut.Coordinates = l.Coordinates[a : b+1]
		cut.Details = routing.Details{
			SAC:     clipRuns(l.Details.SAC, a, b),
			Surface: clipRuns(l.Details.Surface, a, b),
			WayType: clipRuns(l.Details.WayType, a, b),
			Trail:   clipRuns(l.Details.Trail, a, b),
		}
		cut, err := normalizeLeg(cut)
		if err != nil {
			continue // stored legs are valid, and so is any part of them
		}
		from, to := anchors[i], anchors[i+1]
		if a > 0 {
			from = Anchor{Lon: cut.Coordinates[0][0], Lat: cut.Coordinates[0][1]}
		}
		if a > 0 || b < n-1 {
			last := cut.Coordinates[len(cut.Coordinates)-1]
			to = Anchor{Lon: last[0], Lat: last[1], Straight: to.Straight}
		}
		if len(r.Anchors) == 0 {
			r.Anchors = append(r.Anchors, from)
		}
		r.Anchors = append(r.Anchors, to)
		r.Legs = append(r.Legs, cut)
	}
	return r
}

// clipRuns cuts detail runs over segments to the vertices a to b and
// counts them from a.
func clipRuns(runs []routing.Run, a, b int) []routing.Run {
	out := []routing.Run{}
	for _, run := range runs {
		from, to := max(run.From, a), min(run.To, b)
		if to > from {
			out = append(out, routing.Run{From: from - a, To: to - a, Value: run.Value})
		}
	}
	return out
}
