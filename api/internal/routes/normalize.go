// Package routes stores planned routes.
package routes

import (
	"errors"
	"fmt"
	"math"
	"strconv"
	"strings"

	"github.com/tellbow/alvyo/api/internal/routing"
	"github.com/tellbow/alvyo/swiss/geo"
	"github.com/tellbow/alvyo/swiss/stats"
)

// Limits on what a route may contain.
const (
	MaxAnchors  = 200
	MaxVertices = 50_000
	// maxGap is how far (metres) consecutive legs may be apart at their joint.
	maxGap = 50
)

// Covered area: Switzerland and Liechtenstein and 15 km around them (the
// routing graph, infra/data-import/border.geojson), as in the API.
const minLon, maxLon, minLat, maxLat = 5.7, 10.7, 45.65, 47.95

// Elevations a route may have (metres; Switzerland: 193 to 4634).
const minEle, maxEle = -500, 5000

// ErrInvalid wraps validation errors of submitted routes.
var ErrInvalid = errors.New("invalid route")

func invalid(format string, args ...any) error {
	return fmt.Errorf("%w: %s", ErrInvalid, fmt.Sprintf(format, args...))
}

// normalizeLeg validates a submitted leg and recomputes every number that
// derives from its geometry and details, so stored values always match the
// line whatever the client sent.
func normalizeLeg(l routing.Leg) (routing.Leg, error) {
	n := len(l.Coordinates)
	if n < 2 {
		return l, invalid("leg needs at least two points")
	}
	pts := make([]geo.Point, n)
	ele := make([]float64, n)
	for i, c := range l.Coordinates {
		if !finite(c[0], c[1], c[2]) || c[0] < minLon || c[0] > maxLon || c[1] < minLat || c[1] > maxLat {
			return l, invalid("point %d outside the covered area", i)
		}
		if c[2] < minEle || c[2] > maxEle {
			return l, invalid("point %d: elevation %.0f m", i, c[2])
		}
		pts[i] = geo.Point{Lon: c[0], Lat: c[1]}
		ele[i] = c[2]
	}
	seg := make([]float64, n-1)
	for i := range seg {
		seg[i] = geo.Distance(pts[i], pts[i+1])
	}

	var err error
	sacBreakdown, err := breakdown(l.Details.SAC, seg, validSAC)
	if err != nil {
		return l, err
	}
	if l.Surfaces, err = breakdown(l.Details.Surface, seg, validSurface); err != nil {
		return l, err
	}
	if l.WayTypes, err = breakdown(l.Details.WayType, seg, validWayType); err != nil {
		return l, err
	}
	if l.Trails, err = breakdown(l.Details.Trail, seg, validTrail); err != nil {
		return l, err
	}

	st := stats.Compute(pts, ele)
	l.DistanceM = st.DistanceM
	l.AscentM = math.Round(st.AscentM)
	l.DescentM = math.Round(st.DescentM)
	l.EleMinM = st.EleMinM
	l.EleMaxM = st.EleMaxM
	l.DurationS = int(st.Duration.Seconds())
	l.DurationReverseS = int(st.DurationReverse.Seconds())

	grade := 0
	for t := range sacBreakdown {
		g, _ := strconv.Atoi(strings.TrimPrefix(t, "T"))
		grade = max(grade, g)
	}
	l.SAC.Grade = grade
	l.SAC.Max = min(max(l.SAC.Max, grade), 6)
	l.SAC.Breakdown = sacBreakdown
	l.SAC.UnofficialM = math.Round(min(max(l.SAC.UnofficialM, 0), l.DistanceM))
	if l.Warnings == nil {
		l.Warnings = []string{}
	}
	return l, nil
}

// breakdown checks that runs cover all segments in order and sums metres per
// value.
func breakdown(runs []routing.Run, seg []float64, valid func(string) bool) (map[string]float64, error) {
	out := map[string]float64{}
	next := 0
	for _, r := range runs {
		if r.From != next || r.To <= r.From || r.To > len(seg) || !valid(r.Value) {
			return nil, invalid("bad detail run %+v", r)
		}
		for k := r.From; k < r.To; k++ {
			out[r.Value] += seg[k]
		}
		next = r.To
	}
	if next != len(seg) {
		return nil, invalid("detail runs cover %d of %d segments", next, len(seg))
	}
	for k, v := range out {
		out[k] = math.Round(v)
	}
	return out, nil
}

func oneOf(values ...string) func(string) bool {
	return func(s string) bool {
		for _, v := range values {
			if s == v {
				return true
			}
		}
		return false
	}
}

var (
	validSAC     = oneOf("T1", "T2", "T3", "T4", "T5", "T6")
	validSurface = oneOf("paved", "gravel", "natural", "unknown")
	validWayType = oneOf("road", "track", "path", "steps", "unknown")
	validTrail   = oneOf("Wanderweg", "Bergwanderweg", "Alpinwanderweg", "none")
)

func finite(xs ...float64) bool {
	for _, x := range xs {
		if math.IsNaN(x) || math.IsInf(x, 0) {
			return false
		}
	}
	return true
}
