// Package hikingtime implements the Swiss hiking time formula used on the
// yellow signposts of the Swiss hiking trail network.
//
// It is the SchweizMobil variant of the Schweizer Wanderwege formula (valid
// polynomial range ±40 % instead of ±25 %), as used by map.geo.admin.ch:
// geoadmin/mf-geoadmin3 src/components/profile/ProfileService.js, hikingTime().
// Times are pure walking time without breaks.
package hikingtime

// coefficients of the polynomial in the slope s (in tenths, s=1 ⇔ 10 %)
// giving minutes per horizontal kilometre.
var coefficients = [...]float64{
	14.271, 3.6991, 2.5922, -1.4384,
	0.32105, 0.81542, -0.090261, -0.20757,
	0.010192, 0.028588, -0.00057466, -0.0021842,
	1.5176e-5, 8.6894e-5, -1.3584e-7, -1.4026e-6,
}

// MinutesPerKm returns walking minutes per horizontal kilometre on a slope
// s given in tenths (Δh·10/Δd), e.g. s=1 for a 10 % incline. On flat ground
// this is 14.271 min/km (4.2 km/h).
func MinutesPerKm(s float64) float64 {
	switch {
	case s > -4 && s < 4:
		// Horner's scheme for Σ cᵢ·sⁱ.
		m := 0.0
		for i := len(coefficients) - 1; i >= 0; i-- {
			m = m*s + coefficients[i]
		}
		return m
	case s > 0:
		return 17 * s
	default:
		return -9 * s
	}
}

// Minutes returns the walking time in minutes along a profile given as
// cumulative horizontal distance (metres, non-decreasing) and elevation
// (metres) per sample. The result depends on the sampling: use a fixed step
// (see stats) so that times are comparable between routes.
func Minutes(dist, ele []float64) float64 {
	total := 0.0
	for i := 1; i < len(dist); i++ {
		d := dist[i] - dist[i-1]
		if d == 0 {
			continue
		}
		s := (ele[i] - ele[i-1]) * 10 / d
		total += d * MinutesPerKm(s) / 1000
	}
	return total
}

// MinutesReverse returns the walking time for the same profile walked from
// its end to its start.
func MinutesReverse(dist, ele []float64) float64 {
	n := len(dist)
	rd := make([]float64, n)
	re := make([]float64, n)
	for i := range n {
		rd[i] = dist[n-1] - dist[n-1-i]
		re[i] = ele[n-1-i]
	}
	return Minutes(rd, re)
}
