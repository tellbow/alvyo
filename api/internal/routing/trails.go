package routing

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tellbow/odysgeh/swiss/geo"
	"github.com/tellbow/odysgeh/swiss/sac"
)

// trailTolerance is how far (metres) a segment's midpoint may be from an
// official trail to count as on it; covers GPS/OSM vs TLM offsets.
const trailTolerance = 12

// TrailMatcher looks up the official trail category (swissTLM3D) per segment.
type TrailMatcher struct {
	DB *pgxpool.Pool
}

// categorySQL finds, for the midpoint of every segment, the nearest official
// trail within the tolerance. Coordinates are transformed to LV95 for metres.
const categorySQL = `
WITH pts AS (
    SELECT i, ST_Transform(ST_SetSRID(ST_MakePoint(lon, lat), 4326), 2056) AS p
    FROM unnest($1::float8[], $2::float8[]) WITH ORDINALITY AS t(lon, lat, i)
), segs AS (
    SELECT i, ST_LineInterpolatePoint(ST_MakeLine(p, LEAD(p) OVER (ORDER BY i)), 0.5) AS mid
    FROM pts
)
SELECT s.i, COALESCE(t.category, '')
FROM segs s
LEFT JOIN LATERAL (
    SELECT category FROM tlm_hiking_paths h
    WHERE ST_DWithin(h.geom, s.mid, $3)
    ORDER BY h.geom <-> s.mid
    LIMIT 1
) t ON true
WHERE s.mid IS NOT NULL
ORDER BY s.i`

// Categories returns one category per segment (len(pts)-1 values).
func (m *TrailMatcher) Categories(ctx context.Context, pts []geo.Point) ([]sac.Category, error) {
	if len(pts) < 2 {
		return nil, nil
	}
	lons := make([]float64, len(pts))
	lats := make([]float64, len(pts))
	for i, p := range pts {
		lons[i], lats[i] = p.Lon, p.Lat
	}
	rows, err := m.DB.Query(ctx, categorySQL, lons, lats, trailTolerance)
	if err != nil {
		return nil, fmt.Errorf("routing: trail categories: %w", err)
	}
	defer rows.Close()

	out := make([]sac.Category, len(pts)-1)
	for rows.Next() {
		var i int64
		var cat string
		if err := rows.Scan(&i, &cat); err != nil {
			return nil, err
		}
		if idx := int(i) - 1; idx >= 0 && idx < len(out) { // ordinality is 1-based
			out[idx] = sac.ParseCategory(cat)
		}
	}
	return out, rows.Err()
}
