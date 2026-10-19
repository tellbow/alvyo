package lv95

import (
	"math"
	"testing"
)

// FuzzRoundTrip: anywhere in Switzerland and Liechtenstein, WGS84 → LV95 →
// WGS84 lands within a centimetre.
func FuzzRoundTrip(f *testing.F) {
	f.Add(7.438632, 46.951082)
	f.Add(10.49, 45.81)
	f.Fuzz(func(t *testing.T, lon, lat float64) {
		if !(lon >= 5.9 && lon <= 10.5 && lat >= 45.8 && lat <= 47.85) {
			t.Skip()
		}
		lon2, lat2 := ToWGS84(FromWGS84(lon, lat))
		dy := (lat2 - lat) * 111_195
		dx := (lon2 - lon) * 111_195 * math.Cos(lat*math.Pi/180)
		if d := math.Hypot(dx, dy); !(d <= 0.01) {
			t.Fatalf("(%v, %v) off by %.3f m", lon, lat, d)
		}
	})
}
