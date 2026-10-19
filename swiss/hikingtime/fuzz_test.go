package hikingtime

import (
	"math"
	"testing"
)

// FuzzMinutesPerKm: walking always takes time, and steeper (up or down)
// beyond the formula's range never gets faster.
func FuzzMinutesPerKm(f *testing.F) {
	f.Add(0.0)
	f.Add(3.999)
	f.Add(-4.0)
	f.Fuzz(func(t *testing.T, s float64) {
		if math.IsNaN(s) || math.Abs(s) > 1000 {
			t.Skip()
		}
		m := MinutesPerKm(s)
		if !(m > 0) || math.IsInf(m, 0) {
			t.Fatalf("MinutesPerKm(%v) = %v", s, m)
		}
		if math.Abs(s) >= 4 && MinutesPerKm(s+math.Copysign(0.1, s)) < m {
			t.Fatalf("steeper than %v is faster", s)
		}
	})
}

// FuzzMinutes: a profile's time is positive and the sum of its parts.
func FuzzMinutes(f *testing.F) {
	f.Add([]byte{10, 0, 10, 5, 20, 250, 1, 0}, uint8(2))
	f.Fuzz(func(t *testing.T, data []byte, split uint8) {
		// Two bytes per sample: the step (m) and the climb (m, signed).
		dist, ele := []float64{0}, []float64{1500}
		for i := 0; i+1 < len(data); i += 2 {
			dist = append(dist, dist[len(dist)-1]+float64(data[i]))
			ele = append(ele, ele[len(ele)-1]+float64(int8(data[i+1])))
		}
		total := Minutes(dist, ele)
		if total < 0 || (dist[len(dist)-1] > 0 && total == 0) {
			t.Fatalf("%v min for %v m", total, dist[len(dist)-1])
		}
		k := int(split) % len(dist)
		parts := Minutes(dist[:k+1], ele[:k+1]) + Minutes(dist[k:], ele[k:])
		if math.Abs(parts-total) > 1e-9*math.Max(1, total) {
			t.Fatalf("parts %v, whole %v", parts, total)
		}
		if r := MinutesReverse(dist, ele); r < 0 || (dist[len(dist)-1] > 0 && r == 0) {
			t.Fatalf("reverse %v min", r)
		}
	})
}
