package geo

import "math"

// Simplify drops points that lie within tolerance metres of the line through
// their neighbours (Ramer–Douglas–Peucker), e.g. the jitter of a GPS track.
// The first and last points are always kept.
func Simplify(pts []Point, tolerance float64) []Point {
	if len(pts) < 3 {
		return pts
	}
	// Local equirectangular projection in metres; exact enough for the
	// distances involved.
	lat0 := pts[0].Lat * math.Pi / 180
	kx, ky := earthRadius*math.Pi/180*math.Cos(lat0), earthRadius*math.Pi/180
	xy := make([][2]float64, len(pts))
	for i, p := range pts {
		xy[i] = [2]float64{p.Lon * kx, p.Lat * ky}
	}
	keep := make([]bool, len(pts))
	keep[0], keep[len(pts)-1] = true, true
	type span struct{ a, b int }
	stack := []span{{0, len(pts) - 1}}
	for len(stack) > 0 {
		s := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		far, farD := -1, tolerance
		for i := s.a + 1; i < s.b; i++ {
			if d := segDistance(xy[i], xy[s.a], xy[s.b]); d > farD {
				far, farD = i, d
			}
		}
		if far >= 0 {
			keep[far] = true
			stack = append(stack, span{s.a, far}, span{far, s.b})
		}
	}
	out := make([]Point, 0, len(pts))
	for i, p := range pts {
		if keep[i] {
			out = append(out, p)
		}
	}
	return out
}

// segDistance is the distance from p to the segment a–b.
func segDistance(p, a, b [2]float64) float64 {
	dx, dy := b[0]-a[0], b[1]-a[1]
	l2 := dx*dx + dy*dy
	t := 0.0
	if l2 > 0 {
		t = math.Max(0, math.Min(1, ((p[0]-a[0])*dx+(p[1]-a[1])*dy)/l2))
	}
	return math.Hypot(p[0]-(a[0]+t*dx), p[1]-(a[1]+t*dy))
}
