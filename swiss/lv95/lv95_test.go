package lv95

import (
	"math"
	"math/rand/v2"
	"testing"
)

// Reference values from swisstopo REFRAME (geodesy.geo.admin.ch/reframe/wgs84tolv95),
// which uses the rigorous transformation.
var reference = []struct {
	name     string
	lon, lat float64
	e, n     float64
}{
	{"Bern observatory", 7.438632, 46.951082, 2599999.962857628, 1199999.903685084},
	{"Gaflei FL", 9.542797, 47.144722, 2759584.9949880117, 1223666.9567881809},
	{"Sargans", 9.445630, 47.044880, 2752501.213817534, 1212377.6531089202},
	{"Lugano", 8.951052, 46.005010, 2717154.6597349267, 1095957.0679015846},
	{"Geneva", 6.143158, 46.204391, 2500012.7536059143, 1117820.112101925},
	{"Müstair", 10.451360, 46.610000, 2830746.311968735, 1166513.19040166},
}

const tolMetres = 1.5 // approximate formulas: ~1 m

func TestFromWGS84(t *testing.T) {
	for _, r := range reference {
		e, n := FromWGS84(r.lon, r.lat)
		if d := math.Hypot(e-r.e, n-r.n); d > tolMetres {
			t.Errorf("%s: got (%.2f, %.2f), want (%.2f, %.2f), off by %.2f m", r.name, e, n, r.e, r.n, d)
		}
	}
}

func TestToWGS84(t *testing.T) {
	for _, r := range reference {
		lon, lat := ToWGS84(r.e, r.n)
		// Compare in metres: 1° lat ≈ 111 km, 1° lon ≈ 111 km·cos(lat).
		dy := (lat - r.lat) * 111_195
		dx := (lon - r.lon) * 111_195 * math.Cos(r.lat*math.Pi/180)
		if d := math.Hypot(dx, dy); d > tolMetres {
			t.Errorf("%s: got (%.6f, %.6f), want (%.6f, %.6f), off by %.2f m", r.name, lon, lat, r.lon, r.lat, d)
		}
	}
}

func TestRoundTrip(t *testing.T) {
	rng := rand.New(rand.NewPCG(1, 2))
	for range 1000 {
		// Bounding box of Switzerland + Liechtenstein.
		lon := 5.9 + rng.Float64()*(10.5-5.9)
		lat := 45.8 + rng.Float64()*(47.85-45.8)
		e, n := FromWGS84(lon, lat)
		lon2, lat2 := ToWGS84(e, n)
		dy := (lat2 - lat) * 111_195
		dx := (lon2 - lon) * 111_195 * math.Cos(lat*math.Pi/180)
		if d := math.Hypot(dx, dy); d > 0.01 {
			t.Fatalf("round trip (%.6f, %.6f) off by %.2f m", lon, lat, d)
		}
	}
}
