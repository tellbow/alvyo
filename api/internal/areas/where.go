package areas

import (
	"encoding/json"

	"github.com/tellbow/alvyo/swiss/geo"
)

// whereStepM is how densely a line is checked against an area's shape.
const whereStepM = 10

// where returns the parts of line inside the GeoJSON polygons of g, or
// along (within nearM) its lines: where the map goes on a tap. Nil when
// none is found, e.g. a line grazing an edge.
func where(line []geo.Point, g json.RawMessage) [][][2]float64 {
	var geom struct {
		Type        string          `json:"type"`
		Coordinates json.RawMessage `json:"coordinates"`
	}
	if json.Unmarshal(g, &geom) != nil {
		return nil
	}
	var in func(geo.Point) bool
	switch geom.Type {
	case "Polygon", "MultiPolygon":
		var polys [][][][2]float64
		if geom.Type == "Polygon" {
			var p [][][2]float64
			if json.Unmarshal(geom.Coordinates, &p) != nil {
				return nil
			}
			polys = [][][][2]float64{p}
		} else if json.Unmarshal(geom.Coordinates, &polys) != nil {
			return nil
		}
		in = func(p geo.Point) bool {
			for _, poly := range polys {
				if inside(p, poly) {
					return true
				}
			}
			return false
		}
	case "LineString", "MultiLineString":
		var parts [][][2]float64
		if geom.Type == "LineString" {
			var l [][2]float64
			if json.Unmarshal(geom.Coordinates, &l) != nil {
				return nil
			}
			parts = [][][2]float64{l}
		} else if json.Unmarshal(geom.Coordinates, &parts) != nil {
			return nil
		}
		in = func(p geo.Point) bool {
			for _, part := range parts {
				for i := 1; i < len(part); i++ {
					if segmentDistance(p, part[i-1], part[i]) <= nearM {
						return true
					}
				}
			}
			return false
		}
	default:
		return nil
	}

	dense, _ := geo.Densify(line, whereStepM)
	var out [][][2]float64
	for i := 0; i < len(dense); {
		if !in(dense[i]) {
			i++
			continue
		}
		j := i
		for j < len(dense) && in(dense[j]) {
			j++
		}
		if j-i >= 2 {
			var part [][2]float64
			for _, p := range geo.Simplify(dense[i:j], simplifyM) {
				part = append(part, [2]float64{round5(p.Lon), round5(p.Lat)})
			}
			out = append(out, part)
		}
		i = j
	}
	return out
}

// inside reports whether p lies in a GeoJSON polygon (its outer ring
// without the holes): even-odd over all rings.
func inside(p geo.Point, rings [][][2]float64) bool {
	in := false
	for _, ring := range rings {
		for i, j := 0, len(ring)-1; i < len(ring); j, i = i, i+1 {
			a, b := ring[i], ring[j]
			if (a[1] > p.Lat) != (b[1] > p.Lat) && p.Lon < (b[0]-a[0])*(p.Lat-a[1])/(b[1]-a[1])+a[0] {
				in = !in
			}
		}
	}
	return in
}
