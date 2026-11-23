package discover

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// ErrNoCanton means there is no canton with that code.
var ErrNoCanton = errors.New("discover: no such canton")

// The cantons a line crosses, the one with most of it first. From the line
// others see: a recorded hike's hidden start and end tell nothing.
const cantonsSQL = `
SELECT c.code FROM cantons c JOIN routes r ON ST_Intersects(c.geom, r.shown_geom)
WHERE %s
GROUP BY c.code
ORDER BY sum(ST_Length(ST_Intersection(c.geom, r.shown_geom))) DESC, c.code`

// RouteCantons are the codes of the cantons a route crosses, such as BE.
func (s *Store) RouteCantons(ctx context.Context, id uuid.UUID) ([]string, error) {
	return s.cantons(ctx, fmt.Sprintf(cantonsSQL, "r.id = $1"), id)
}

// JourneyCantons are the codes of the cantons a journey's stages cross.
func (s *Store) JourneyCantons(ctx context.Context, id uuid.UUID) ([]string, error) {
	return s.cantons(ctx, fmt.Sprintf(cantonsSQL, "r.journey_id = $1"), id)
}

func (s *Store) cantons(ctx context.Context, sql string, id uuid.UUID) ([]string, error) {
	rows, err := s.DB.Query(ctx, sql, id)
	if err != nil {
		return nil, fmt.Errorf("discover: cantons: %w", err)
	}
	return pgx.CollectRows(rows, pgx.RowTo[string])
}

// CantonItem is a public route or journey in a canton's list.
type CantonItem struct {
	Kind      string  `json:"kind" enum:"route,journey"`
	ID        string  `json:"id" format:"uuid"`
	Title     string  `json:"title"`
	DistanceM float64 `json:"distance_m"`
	AscentM   float64 `json:"ascent_m"`
	DurationS int     `json:"duration_s" doc:"Journeys: all stages together"`
	SACGrade  int     `json:"sac_grade"`
	SACMax    int     `json:"sac_max"`
	Stages    int     `json:"stages" doc:"Journeys only"`
}

// CantonCount is how many public routes and journeys cross a canton.
type CantonCount struct {
	Code  string `json:"code"`
	Items int    `json:"items"`
}

// MaxCanton is the most items a canton's list holds.
const MaxCanton = 500

// inCanton are the public routes (not recorded hikes) and journeys of users
// not banned that cross a canton, as discovery and the sitemap list them.
const inCanton = `
WITH items AS (
	SELECT 'route' AS kind, r.id, r.title, r.distance_m::float8 AS distance_m, r.ascent_m::float8 AS ascent_m,
		r.duration_s, r.sac_grade, r.sac_max, 0 AS stages, c.code
	FROM routes r
	JOIN users u ON u.id = r.owner_id AND u.banned_at IS NULL
	JOIN cantons c ON ST_Intersects(c.geom, r.shown_geom)
	WHERE r.visibility = 'public' AND r.journey_id IS NULL AND r.hiked_at IS NULL
	UNION ALL
	SELECT 'journey', j.id, j.title, t.distance_m, t.ascent_m, t.duration_s, t.sac_grade, t.sac_max, t.stages, c.code
	FROM journeys j
	JOIN users u ON u.id = j.owner_id AND u.banned_at IS NULL
	CROSS JOIN LATERAL (
		SELECT sum(sr.distance_m)::float8 AS distance_m, sum(sr.ascent_m)::float8 AS ascent_m,
			sum(sr.duration_s)::int AS duration_s, max(sr.sac_grade)::int AS sac_grade,
			max(sr.sac_max)::int AS sac_max, count(*)::int AS stages
		FROM routes sr WHERE sr.journey_id = j.id
	) t
	JOIN cantons c ON EXISTS (
		SELECT 1 FROM routes sr WHERE sr.journey_id = j.id AND ST_Intersects(c.geom, sr.shown_geom))
	WHERE j.visibility = 'public' AND t.stages > 0
)`

// InCanton lists a canton's public routes and journeys by title.
func (s *Store) InCanton(ctx context.Context, code string) ([]CantonItem, error) {
	var known bool
	if err := s.DB.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM cantons WHERE code = $1)`, code).Scan(&known); err != nil {
		return nil, fmt.Errorf("discover: canton: %w", err)
	}
	if !known {
		return nil, ErrNoCanton
	}
	rows, err := s.DB.Query(ctx, inCanton+`
SELECT kind, id::text, title, distance_m, ascent_m, duration_s, sac_grade, sac_max, stages
FROM items WHERE code = $1 ORDER BY title, id LIMIT $2`, code, MaxCanton)
	if err != nil {
		return nil, fmt.Errorf("discover: canton: %w", err)
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[CantonItem])
}

// Cantons counts the public routes and journeys of every canton that has any.
func (s *Store) Cantons(ctx context.Context) ([]CantonCount, error) {
	rows, err := s.DB.Query(ctx, inCanton+`
SELECT code, count(*)::int FROM items GROUP BY code ORDER BY code`)
	if err != nil {
		return nil, fmt.Errorf("discover: cantons: %w", err)
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[CantonCount])
}
