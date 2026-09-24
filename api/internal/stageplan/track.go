// Package stageplan splits a long hike into days that end where one can
// sleep: huts, hotels, campsites, or a stop to travel home.
package stageplan

import (
	"math"

	"github.com/tellbow/odysgeh/api/internal/routing"
	"github.com/tellbow/odysgeh/swiss/geo"
	"github.com/tellbow/odysgeh/swiss/hikingtime"
	"github.com/tellbow/odysgeh/swiss/stats"
)

// Track is a whole route as one line: vertices with elevation and what is
// known about each segment, to cut into stages anywhere.
type Track struct {
	Coords [][3]float64
	segs   []segment // len(Coords)-1
}

type segment struct {
	sac, surface, wayType, trail string
	sacMax                       int     // upper end of the leg's SAC range
	unofficial                   float64 // share of the leg graded by guess
}

// jointM: legs that end and start this close share the vertex.
const jointM = 1.0

// FromLegs joins computed legs into one track.
func FromLegs(legs []routing.Leg) Track {
	var t Track
	for _, l := range legs {
		n := len(l.Coordinates)
		if n < 2 {
			continue
		}
		unofficial := 0.0
		if l.DistanceM > 0 {
			unofficial = math.Min(l.SAC.UnofficialM/l.DistanceM, 1)
		}
		at := func(runs []routing.Run, k int) string {
			for _, r := range runs {
				if k >= r.From && k < r.To {
					return r.Value
				}
			}
			return ""
		}
		coords := l.Coordinates
		if m := len(t.Coords); m > 0 {
			last, first := t.Coords[m-1], coords[0]
			if geo.Distance(point(last), point(first)) < jointM {
				coords = coords[1:]
			} else {
				// Not joined (e.g. a straight leg to a place): a straight
				// segment like its successor's first.
				t.segs = append(t.segs, segmentOf(l, at, 0, unofficial))
			}
		}
		t.Coords = append(t.Coords, coords...)
		for k := range n - 1 {
			t.segs = append(t.segs, segmentOf(l, at, k, unofficial))
		}
	}
	return t
}

func segmentOf(l routing.Leg, at func([]routing.Run, int) string, k int, unofficial float64) segment {
	return segment{
		sac: at(l.Details.SAC, k), surface: at(l.Details.Surface, k),
		wayType: at(l.Details.WayType, k), trail: at(l.Details.Trail, k),
		sacMax: l.SAC.Max, unofficial: unofficial,
	}
}

func point(c [3]float64) geo.Point { return geo.Point{Lon: c[0], Lat: c[1]} }

// Points returns the vertices (lon, lat).
func (t Track) Points() []geo.Point {
	pts := make([]geo.Point, len(t.Coords))
	for i, c := range t.Coords {
		pts[i] = point(c)
	}
	return pts
}

// Seconds returns the Swiss hiking time from the start to each vertex,
// computed on the evenly resampled profile as for route totals.
func (t Track) Seconds() []float64 {
	n := len(t.Coords)
	if n == 0 {
		return nil
	}
	dist := geo.CumulativeDistance(t.Points())
	ele := make([]float64, n)
	for i, c := range t.Coords {
		ele[i] = c[2]
	}
	rd, re := geo.Resample(dist, ele, stats.ProfileStep)
	cum := make([]float64, len(rd))
	for i := 1; i < len(rd); i++ {
		cum[i] = cum[i-1] + 60*hikingtime.Minutes(rd[i-1:i+1], re[i-1:i+1])
	}
	return geo.Interpolate(rd, cum, dist)
}

// Legs cuts vertices from to to into legs of about splitM metres, for a
// stage route that can be edited in parts like an imported one.
func (t Track) Legs(from, to int, splitM float64) []routing.Leg {
	var legs []routing.Leg
	start := from
	run := 0.0
	for i := from + 1; i <= to; i++ {
		run += geo.Distance(point(t.Coords[i-1]), point(t.Coords[i]))
		if i == to || run >= splitM {
			legs = append(legs, t.leg(start, i))
			start, run = i, 0
		}
	}
	return legs
}

// leg is the part from vertex a to b; its numbers are left for
// routes.Check to compute.
func (t Track) leg(a, b int) routing.Leg {
	l := routing.Leg{
		Coordinates: append([][3]float64(nil), t.Coords[a:b+1]...),
		Warnings:    []string{},
	}
	runs := func(value func(segment) string) []routing.Run {
		var out []routing.Run
		for k := a; k < b; k++ {
			v := value(t.segs[k])
			if n := len(out); n > 0 && out[n-1].Value == v {
				out[n-1].To = k - a + 1
				continue
			}
			out = append(out, routing.Run{From: k - a, To: k - a + 1, Value: v})
		}
		return out
	}
	l.Details = routing.Details{
		SAC:     runs(func(s segment) string { return s.sac }),
		Surface: runs(func(s segment) string { return s.surface }),
		WayType: runs(func(s segment) string { return s.wayType }),
		Trail:   runs(func(s segment) string { return s.trail }),
	}
	for k := a; k < b; k++ {
		l.SAC.Max = max(l.SAC.Max, t.segs[k].sacMax)
		l.SAC.UnofficialM += geo.Distance(point(t.Coords[k]), point(t.Coords[k+1])) * t.segs[k].unofficial
	}
	return l
}
