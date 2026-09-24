// Package places looks up reference places for stage starts and ends: public
// transport stops and huts and accommodation. Search also finds swisstopo's
// geographical names and addresses.
package places

import (
	"context"
	"fmt"
	"math"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Kinds of places.
var Kinds = []string{"pt_stop", "hut", "hotel", "campsite"}

// Search bounds.
const (
	nearbyRadius = 3000   // metres, without a name filter
	searchRadius = 30_000 // metres, with a name filter
	MaxResults   = 30
)

// Place is a stop, hut or accommodation.
type Place struct {
	ID   string `json:"id" format:"uuid"`
	Kind string `json:"kind" enum:"pt_stop,hut,hotel,campsite"`
	Name string `json:"name"`
	// Detail: transport modes of a stop ("Bus", "Zug" …) or the OSM tourism
	// value (alpine_hut, wilderness_hut, guest_house …).
	Detail string `json:"detail"`
	Ref    string `json:"ref,omitempty" doc:"Didok number of a stop, for timetable queries"`
	// Website of a hut or accommodation, from OpenStreetMap where known.
	Website string     `json:"website,omitempty"`
	At      [2]float64 `json:"at" doc:"lon, lat"`
	// DistanceM is the distance to the point asked about (the route end for
	// stage places).
	DistanceM float64 `json:"distance_m"`
	// Suggested marks the nearest stop or hut to a stage end when the author
	// has not chosen one.
	Suggested bool `json:"suggested,omitempty"`
}

// Query selects places around a point.
type Query struct {
	Lon, Lat float64
	Name     string   // optional substring of the name
	Kinds    []string // empty: all
	Limit    int
}

// Store reads places.
type Store struct {
	DB *pgxpool.Pool
	// Names adds swisstopo's names to Search; nil: only our places.
	Names Names
}

// Nearby returns places around a point, nearest first: within 3 km, or 30 km
// when filtering by name.
func (s *Store) Nearby(ctx context.Context, q Query) ([]Place, error) {
	radius := nearbyRadius
	if q.Name != "" {
		radius = searchRadius
	}
	limit := q.Limit
	if limit <= 0 || limit > MaxResults {
		limit = MaxResults
	}
	rows, err := s.DB.Query(ctx, `
		WITH here AS (SELECT ST_SetSRID(ST_MakePoint($1, $2), 4326) AS g)
		SELECT p.id, p.kind, p.name, p.detail, CASE WHEN p.source = 'didok' THEN p.source_id ELSE '' END,
			ST_X(p.geom), ST_Y(p.geom), ST_Distance(p.geom::geography, here.g::geography)
		FROM places p, here
		WHERE ST_DWithin(p.geom::geography, here.g::geography, $3)
			AND ($4 = '' OR p.name ILIKE '%' || $4 || '%')
			AND (coalesce(cardinality($5::text[]), 0) = 0 OR p.kind = ANY($5))
		ORDER BY p.geom <-> here.g
		LIMIT $6`, q.Lon, q.Lat, radius, q.Name, q.Kinds, limit)
	if err != nil {
		return nil, fmt.Errorf("places: nearby: %w", err)
	}
	defer rows.Close()
	out := []Place{}
	for rows.Next() {
		var p Place
		if err := rows.Scan(&p.ID, &p.Kind, &p.Name, &p.Detail, &p.Ref, &p.At[0], &p.At[1], &p.DistanceM); err != nil {
			return nil, err
		}
		p.DistanceM = math.Round(p.DistanceM)
		out = append(out, p)
	}
	return out, rows.Err()
}
