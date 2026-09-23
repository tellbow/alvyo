// Package geo has small geometry helpers for hiking routes: distances on the
// sphere, densifying lines, sampling profiles and downsampling them for
// display.
package geo

import (
	"math"
	"slices"
	"sort"
)

// Point is a WGS84 position in degrees.
type Point struct{ Lon, Lat float64 }

// earthRadius is the mean Earth radius in metres (IUGG).
const earthRadius = 6371008.8

// Distance returns the great-circle distance between a and b in metres.
func Distance(a, b Point) float64 {
	const rad = math.Pi / 180
	dLat := (b.Lat - a.Lat) * rad
	dLon := (b.Lon - a.Lon) * rad
	h := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(a.Lat*rad)*math.Cos(b.Lat*rad)*math.Sin(dLon/2)*math.Sin(dLon/2)
	return 2 * earthRadius * math.Asin(math.Sqrt(h))
}

// CumulativeDistance returns, for each point, the distance in metres along
// the line from pts[0].
func CumulativeDistance(pts []Point) []float64 {
	d := make([]float64, len(pts))
	for i := 1; i < len(pts); i++ {
		d[i] = d[i-1] + Distance(pts[i-1], pts[i])
	}
	return d
}

// Densify inserts evenly spaced points so that no segment is longer than
// maxStep metres. orig[i] is the index of input point i in out, which lets
// callers remap per-vertex data such as index ranges.
func Densify(pts []Point, maxStep float64) (out []Point, orig []int) {
	orig = make([]int, len(pts))
	if len(pts) == 0 {
		return nil, orig
	}
	out = append(out, pts[0])
	for i := 1; i < len(pts); i++ {
		a, b := pts[i-1], pts[i]
		if n := int(math.Ceil(Distance(a, b) / maxStep)); n > 1 {
			for k := 1; k < n; k++ {
				f := float64(k) / float64(n)
				out = append(out, Point{a.Lon + (b.Lon-a.Lon)*f, a.Lat + (b.Lat-a.Lat)*f})
			}
		}
		orig[i] = len(out)
		out = append(out, b)
	}
	return out, orig
}

// Interpolate evaluates the piecewise-linear function through (xs, ys) at
// each value of at. xs must be non-decreasing; values outside its range take
// the nearest endpoint.
func Interpolate(xs, ys, at []float64) []float64 {
	out := make([]float64, len(at))
	if len(xs) == 0 {
		return out
	}
	last := len(xs) - 1
	for i, x := range at {
		switch {
		case x <= xs[0]:
			out[i] = ys[0]
		case x >= xs[last]:
			out[i] = ys[last]
		default:
			j := sort.SearchFloat64s(xs, x) // xs[j-1] < x <= xs[j]
			x0, x1 := xs[j-1], xs[j]
			if x1 == x0 {
				out[i] = ys[j]
				continue
			}
			out[i] = ys[j-1] + (ys[j]-ys[j-1])*(x-x0)/(x1-x0)
		}
	}
	return out
}

// Resample samples the piecewise-linear function through (xs, ys) every step
// from xs[0] to the end. The last sample is always the end point, so the
// final interval may be shorter than step.
func Resample(xs, ys []float64, step float64) (rx, ry []float64) {
	if len(xs) == 0 {
		return nil, nil
	}
	start, end := xs[0], xs[len(xs)-1]
	for x := start; x < end; x += step {
		rx = append(rx, x)
	}
	rx = append(rx, end)
	return rx, Interpolate(xs, ys, rx)
}

// LTTB picks at most n indices of the series (xs, ys) with the
// Largest-Triangle-Three-Buckets algorithm, which keeps the visual shape of a
// line chart. The first and last points are always kept, and so are the
// global minimum and maximum of ys so that summits never disappear from an
// elevation profile. Indices are returned in increasing order.
func LTTB(xs, ys []float64, n int) []int {
	total := len(xs)
	n = max(n, 3)
	if n >= total {
		return seq(total)
	}

	sel := make([]int, 0, n)
	sel = append(sel, 0)
	bucket := float64(total-2) / float64(n-2)
	a := 0
	for i := range n - 2 {
		// Average of the next bucket (or the last point) is the third vertex.
		nextStart := int(float64(i+1)*bucket) + 1
		nextEnd := min(int(float64(i+2)*bucket)+1, total)
		var avgX, avgY float64
		if nextStart >= total-1 {
			avgX, avgY = xs[total-1], ys[total-1]
		} else {
			for j := nextStart; j < nextEnd; j++ {
				avgX += xs[j]
				avgY += ys[j]
			}
			cnt := float64(nextEnd - nextStart)
			avgX /= cnt
			avgY /= cnt
		}

		start := int(float64(i)*bucket) + 1
		end := int(float64(i+1)*bucket) + 1
		best, bestArea := start, -1.0
		for j := start; j < end; j++ {
			area := math.Abs((xs[a]-avgX)*(ys[j]-ys[a]) - (xs[a]-xs[j])*(avgY-ys[a]))
			if area > bestArea {
				best, bestArea = j, area
			}
		}
		sel = append(sel, best)
		a = best
	}
	sel = append(sel, total-1)
	return keepExtremes(sel, ys)
}

// keepExtremes swaps the global min and max of ys into sel, replacing the
// nearest interior selection, so the count stays the same.
func keepExtremes(sel []int, ys []float64) []int {
	lo, hi := 0, 0
	for i, y := range ys {
		if y < ys[lo] {
			lo = i
		}
		if y > ys[hi] {
			hi = i
		}
	}
	protected := map[int]bool{sel[0]: true, sel[len(sel)-1]: true}
	for _, e := range []int{lo, hi} {
		if slices.Contains(sel, e) {
			protected[e] = true
			continue
		}
		nearest := -1
		for k, s := range sel {
			if protected[s] {
				continue
			}
			if nearest < 0 || abs(s-e) < abs(sel[nearest]-e) {
				nearest = k
			}
		}
		if nearest < 0 {
			continue
		}
		sel[nearest] = e
		protected[e] = true
	}
	sort.Ints(sel)
	return sel
}

func seq(n int) []int {
	s := make([]int, n)
	for i := range s {
		s[i] = i
	}
	return s
}

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}
