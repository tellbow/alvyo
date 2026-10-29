// Package steep says how steep the terrain is along a line, in the classes
// of avalanche and snow advice: from 25°, 30° and 35°.
package steep

import (
	"context"
	"math"

	"github.com/tellbow/alvyo/swiss/geo"
)

const (
	// stepM is how densely a line is sampled; Slope measures over 20 m.
	stepM = 10
	// MaxLineM bounds what is sampled.
	MaxLineM = 500_000
)

// Bounds are the lower ends of classes 1, 2 and 3 in degrees.
var Bounds = [3]float64{25, 30, 35}

// Terrain gives the slope of the terrain in degrees, NaN where unknown.
type Terrain interface {
	Slope(p geo.Point) (float64, error)
}

// Part is a part of a line in one class from 25° on; flatter or unknown
// terrain is left out.
type Part struct {
	FromM float64 `json:"from_m" doc:"From the start of the line"`
	ToM   float64 `json:"to_m"`
	Class int     `json:"class" minimum:"1" maximum:"3" doc:"1: 25–30°, 2: 30–35°, 3: steeper"`
}

// Steepness is how steep the terrain is along a line.
type Steepness struct {
	Known     bool    `json:"known" doc:"Whether the terrain's slope is known (swissALTI3D: Switzerland only)"`
	SteepM    float64 `json:"steep_m" doc:"On terrain steeper than 30°"`
	Stretches []Part  `json:"stretches"`
}

// Of samples the slope every 10 m of line; terrain nil: unknown.
func Of(ctx context.Context, terrain Terrain, line []geo.Point) (Steepness, error) {
	out := Steepness{Stretches: []Part{}, Known: terrain != nil}
	if terrain == nil || len(line) < 2 {
		return out, nil
	}
	pts, _ := geo.Densify(line, stepM)
	dist := geo.CumulativeDistance(pts)
	known := false
	for i := range len(pts) - 1 {
		if err := ctx.Err(); err != nil {
			return out, err
		}
		a, b := pts[i], pts[i+1]
		deg, err := terrain.Slope(geo.Point{Lon: (a.Lon + b.Lon) / 2, Lat: (a.Lat + b.Lat) / 2})
		if err != nil {
			return out, err
		}
		known = known || !math.IsNaN(deg)
		c := class(deg)
		if c >= 2 {
			out.SteepM += dist[i+1] - dist[i]
		}
		if c == 0 {
			continue
		}
		// One piece after another in the same class is one stretch.
		if n := len(out.Stretches); n > 0 && out.Stretches[n-1].Class == c && out.Stretches[n-1].ToM == math.Round(dist[i]) {
			out.Stretches[n-1].ToM = math.Round(dist[i+1])
		} else {
			out.Stretches = append(out.Stretches, Part{FromM: math.Round(dist[i]), ToM: math.Round(dist[i+1]), Class: c})
		}
	}
	out.Known = known
	out.SteepM = math.Round(out.SteepM)
	return out, nil
}

// class of a slope; 0 below 25° and unknown (NaN).
func class(deg float64) int {
	c := 0
	for i, b := range Bounds {
		if deg >= b {
			c = i + 1
		}
	}
	return c
}
