// Package lv95 converts between WGS84 and the Swiss LV95 (EPSG:2056)
// coordinate system using swisstopo's approximate formulas, which are
// accurate to about 1 m inside Switzerland and Liechtenstein.
//
// Source: swisstopo, "Approximate formulas for the transformation between
// Swiss projection coordinates and WGS84".
package lv95

// FromWGS84 converts longitude/latitude in degrees to LV95 easting/northing
// in metres.
func FromWGS84(lon, lat float64) (e, n float64) {
	// Auxiliary values: differences to Bern in units of 10000".
	phi := (lat*3600 - 169028.66) / 10000
	lam := (lon*3600 - 26782.5) / 10000

	e = 2600072.37 +
		211455.93*lam -
		10938.51*lam*phi -
		0.36*lam*phi*phi -
		44.54*lam*lam*lam
	n = 1200147.07 +
		308807.95*phi +
		3745.25*lam*lam +
		76.63*phi*phi -
		194.56*lam*lam*phi +
		119.79*phi*phi*phi
	return e, n
}

// ToWGS84 converts LV95 easting/northing in metres to longitude/latitude in
// degrees. The approximate inverse formula alone is only good to ~3 m, so the
// result is refined against FromWGS84 until both directions agree.
func ToWGS84(e, n float64) (lon, lat float64) {
	lon0, lat0 := approxToWGS84(e, n)
	lon, lat = lon0, lat0
	for range 2 {
		// Push the estimate by the error the approximation makes at the
		// point FromWGS84 maps it to.
		lon1, lat1 := approxToWGS84(FromWGS84(lon, lat))
		lon += lon0 - lon1
		lat += lat0 - lat1
	}
	return lon, lat
}

func approxToWGS84(e, n float64) (lon, lat float64) {
	// Auxiliary values: differences to Bern in units of 1000 km.
	y := (e - 2600000) / 1000000
	x := (n - 1200000) / 1000000

	lam := 2.6779094 +
		4.728982*y +
		0.791484*y*x +
		0.1306*y*x*x -
		0.0436*y*y*y
	phi := 16.9023892 +
		3.238272*x -
		0.270978*y*y -
		0.002528*x*x -
		0.0447*y*y*x -
		0.0140*x*x*x

	// Units of 10000" → degrees.
	return lam * 100 / 36, phi * 100 / 36
}
