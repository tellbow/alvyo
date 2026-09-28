package places

import (
	"context"
	"fmt"
	"math"
	"strings"

	"github.com/tellbow/alvyo/swiss/geo"
)

// PoiKinds are the points of interest along routes.
var PoiKinds = []string{"peak", "viewpoint", "waterfall", "water", "shelter"}

// alongM: points of interest this close to a line are on the way.
const alongM = 200

// Poi is a point of interest along a line.
type Poi struct {
	Kind   string     `json:"kind" enum:"peak,viewpoint,waterfall,water,shelter"`
	Name   string     `json:"name" doc:"Empty for many drinking water points and shelters"`
	Ele    *int       `json:"ele,omitempty" doc:"Summits: height in metres"`
	At     [2]float64 `json:"at" doc:"lon, lat"`
	AlongM float64    `json:"along_m" doc:"How far along the line"`
	OffM   float64    `json:"off_m" doc:"How far from the line"`
}

// Along returns the points of interest within 200 m of line, in the order
// they come; at most 300.
func (s *Store) Along(ctx context.Context, line []geo.Point) ([]Poi, error) {
	if len(line) < 2 {
		return []Poi{}, nil
	}
	var b strings.Builder
	b.WriteString("LINESTRING(")
	for i, p := range line {
		if i > 0 {
			b.WriteByte(',')
		}
		fmt.Fprintf(&b, "%.6f %.6f", p.Lon, p.Lat)
	}
	b.WriteByte(')')
	// A box around the line uses the index; the distance is then measured.
	rows, err := s.DB.Query(ctx, `
		WITH l AS (SELECT ST_GeomFromText($1, 4326) AS g)
		SELECT p.kind, p.name, p.ele, ST_X(p.geom), ST_Y(p.geom),
			ST_LineLocatePoint(l.g, p.geom) * ST_Length(l.g::geography),
			ST_Distance(p.geom::geography, l.g::geography) AS off
		FROM pois p, l
		WHERE p.geom && ST_Expand(l.g, 0.003) AND ST_DWithin(p.geom::geography, l.g::geography, $2)
		ORDER BY 6
		LIMIT 300`, b.String(), alongM)
	if err != nil {
		return nil, fmt.Errorf("places: along: %w", err)
	}
	defer rows.Close()
	out := []Poi{}
	for rows.Next() {
		var p Poi
		if err := rows.Scan(&p.Kind, &p.Name, &p.Ele, &p.At[0], &p.At[1], &p.AlongM, &p.OffM); err != nil {
			return nil, err
		}
		p.AlongM, p.OffM = math.Round(p.AlongM), math.Round(p.OffM)
		out = append(out, p)
	}
	return out, rows.Err()
}
