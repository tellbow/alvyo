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
	// do the same (docs/hiking-time.md: 3 m undercounted ascent by 9 %).
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

// ascent sums climbs and descents with hysteresis: the reference elevation
// only moves once the profile has left it by more than threshold.
func ascent(ele []float64, threshold float64) (up, down float64) {
	if len(ele) == 0 {
		return 0, 0
	}
	ref := ele[0]
	for _, e := range ele[1:] {
		switch d := e - ref; {
		case d > threshold:
			up += d
			ref = e
		case d < -threshold:
			down -= d
			ref = e
		}
	}
	// Count the remainder towards the end point so a steady finish isn't lost.
	if d := ele[len(ele)-1] - ref; d > 0 {
		up += d
	} else {
		down -= d
	}
	return up, down
}

func minutes(m float64) time.Duration {
	return time.Duration(m * float64(time.Minute)).Round(time.Second)
}
