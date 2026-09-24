// Package stats computes the summary numbers shown for a hiking route:
// distance, ascent/descent, elevation range and Swiss hiking time.
package stats

import (
	"math"
	"time"

	"github.com/tellbow/odysgeh/swiss/geo"
	"github.com/tellbow/odysgeh/swiss/hikingtime"
)

const (
	// ProfileStep is the fixed sampling interval in metres for hiking time and
	// ascent. The hiking time formula depends on sampling density, so it must
	// be the same for every route (calibrated in docs/hiking-time.md).
	ProfileStep = 10.0
	// AscentThreshold in metres would suppress elevation noise: a climb or
	// descent only counts once it exceeds this amount. The official Wanderland
	// figures count every climb, and swissALTI3D at 10 m is smooth enough to
	// do the same (docs/hiking-time.md: 3 m undercounted ascent by 4 %).
	AscentThreshold = 0.0
)

// Stats summarises a route.
type Stats struct {
	DistanceM       float64
	AscentM         float64
	DescentM        float64
	EleMinM         float64
	EleMaxM         float64
	Duration        time.Duration // Swiss hiking time, start → end
	DurationReverse time.Duration // Swiss hiking time, end → start
}

// Compute returns the stats of a line with one elevation value per point.
func Compute(pts []geo.Point, ele []float64) Stats {
	return ComputeWith(pts, ele, ProfileStep, AscentThreshold)
}

// ComputeWith is Compute with another profile step and ascent threshold, for
// calibration (cmd/calibrate).
func ComputeWith(pts []geo.Point, ele []float64, step, threshold float64) Stats {
	if len(pts) < 2 {
		return Stats{}
	}
	dist := geo.CumulativeDistance(pts)
	rd, re := geo.Resample(dist, ele, step)
	up, down := ascent(re, threshold)

	lo, hi := math.Inf(1), math.Inf(-1)
	for _, e := range ele {
		lo, hi = min(lo, e), max(hi, e)
	}
	return Stats{
		DistanceM:       dist[len(dist)-1],
		AscentM:         up,
		DescentM:        down,
		EleMinM:         lo,
		EleMaxM:         hi,
		Duration:        minutes(hikingtime.Minutes(rd, re)),
		DurationReverse: minutes(hikingtime.MinutesReverse(rd, re)),
	}
}

// ascent sums climbs and descents with hysteresis: a climb counts up to its
// peak (a descent down to its low point) once the profile has turned back by
// more than threshold; smaller turns are noise within the climb.
func ascent(ele []float64, threshold float64) (up, down float64) {
	if len(ele) == 0 {
		return 0, 0
	}
	from, extreme := ele[0], ele[0] // start and peak (or low point) of the current climb (or descent)
	dir := 0                        // +1 climbing, -1 descending, 0 not yet known
	for _, e := range ele[1:] {
		switch {
		case dir == 0 && e-from > threshold:
			dir, extreme = 1, e
		case dir == 0 && from-e > threshold:
			dir, extreme = -1, e
		case dir == 1 && e >= extreme:
			extreme = e
		case dir == 1 && extreme-e > threshold:
			up += extreme - from
			from, extreme, dir = extreme, e, -1
		case dir == -1 && e <= extreme:
			extreme = e
		case dir == -1 && e-extreme > threshold:
			down += from - extreme
			from, extreme, dir = extreme, e, 1
		}
	}
	// The last climb or descent, then what is left to the end point, so a
	// steady finish isn't lost.
	switch dir {
	case 1:
		up += extreme - from
		from = extreme
	case -1:
		down += from - extreme
		from = extreme
	}
	if d := ele[len(ele)-1] - from; d > 0 {
		up += d
	} else {
		down -= d
	}
	return up, down
}

func minutes(m float64) time.Duration {
	return time.Duration(m * float64(time.Minute)).Round(time.Second)
}
