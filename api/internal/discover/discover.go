// Package discover finds public routes and journeys in a map area.
package discover

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tellbow/alvyo/api/internal/official"
)

// MaxLimit is the most items one search returns.
const MaxLimit = 50

// Store searches public content.
type Store struct {
	DB *pgxpool.Pool
}

// Query is a search in the map view West/South/East/North (WGS84).
type Query struct {
	West, South, East, North float64
	Kind                     string // "route", "journey" or "" for both
	SACMax                   int    // hardest SAC grade allowed; 0 for any
	// Hiking time bounds in seconds (0: none). For journeys they apply to
	// the longest stage.
	MinDurationS, MaxDurationS int
	// Official is "only" for the official Wanderland routes, "none" for
	// those of people, "" for both.
	Official string
	Limit    int
}

// Item is a public route or journey found.
type Item struct {
	Kind          string  `json:"kind" enum:"route,journey"`
	ID            string  `json:"id" format:"uuid"`
	Title         string  `json:"title"`
	OwnerUsername string  `json:"owner_username"`
	DistanceM     float64 `json:"distance_m"`
	AscentM       float64 `json:"ascent_m"`
	DurationS     int     `json:"duration_s" doc:"Journeys: all stages together"`
	LongestS      int     `json:"longest_s" doc:"Journeys: the longest stage; routes: as duration_s"`
	SACGrade      int     `json:"sac_grade"`
	SACMax        int     `json:"sac_max"`
	Stages        int     `json:"stages" doc:"Journeys only"`
	// Official is set for the official Wanderland routes.
	Official *official.Info `json:"official,omitempty"`
	// Lines are simplified (lon, lat) lines for the map.
	Lines [][][2]float64 `json:"lines"`
}

// searchSQL finds the nearest $9 public routes and journeys, walking the
// spatial indexes outwards from the centre of the view ($11, $12), and only
// then builds titles, totals and simplified lines for those found. Journeys
// are found through their nearest stage routes (the first 1000).
const searchSQL = `
WITH found AS (
	(SELECT 'route' AS kind, r.id, r.shown_geom <-> ST_Point($11, $12, 4326) AS d
	FROM routes r JOIN users u ON u.id = r.owner_id AND u.banned_at IS NULL
	WHERE $5::text IN ('', 'route') AND r.visibility = 'public' AND r.journey_id IS NULL
		AND ST_Intersects(r.shown_geom, ST_MakeEnvelope($1, $2, $3, $4, 4326))
		AND ($6::int = 0 OR r.sac_grade <= $6::int) AND r.duration_s BETWEEN $7 AND $8
		AND ($13::text = '' OR EXISTS (SELECT 1 FROM official o WHERE o.route_id = r.id) = ($13 = 'only'))
	ORDER BY r.shown_geom <-> ST_Point($11, $12, 4326) LIMIT $9)
	UNION ALL
	(SELECT 'journey', near.journey_id, near.d
	FROM (
		SELECT journey_id, min(d) AS d
		FROM (
			SELECT sr.journey_id, sr.geom <-> ST_Point($11, $12, 4326) AS d
			FROM routes sr
			JOIN journeys j ON j.id = sr.journey_id AND j.visibility = 'public'
			JOIN users u ON u.id = j.owner_id AND u.banned_at IS NULL
			WHERE $5::text IN ('', 'journey') AND sr.journey_id IS NOT NULL
				AND ST_Intersects(sr.geom, ST_MakeEnvelope($1, $2, $3, $4, 4326))
				AND ($13::text = '' OR EXISTS (SELECT 1 FROM official o WHERE o.journey_id = j.id) = ($13 = 'only'))
			ORDER BY sr.geom <-> ST_Point($11, $12, 4326) LIMIT 1000
		) stage
		GROUP BY journey_id
	) near
	CROSS JOIN LATERAL (
		SELECT max(sr.duration_s) AS longest_s, max(sr.sac_grade) AS sac_grade
		FROM stages st JOIN routes sr ON sr.id = st.route_id
		WHERE st.journey_id = near.journey_id
	) js
	WHERE ($6::int = 0 OR js.sac_grade <= $6::int) AND js.longest_s BETWEEN $7 AND $8
	ORDER BY near.d, near.journey_id LIMIT $9)
), top AS (
	SELECT * FROM found ORDER BY d, id LIMIT $9
)
SELECT top.kind, top.id, coalesce(r.title, j.title), u.username,
	coalesce(r.distance_m, js.distance_m, 0)::float8, coalesce(r.ascent_m, js.ascent_m, 0)::float8,
	coalesce(r.duration_s, js.duration_s, 0)::int, coalesce(r.duration_s, js.longest_s, 0)::int,
	coalesce(r.sac_grade, js.sac_grade, 0)::int, coalesce(r.sac_max, js.sac_max, 0)::int, coalesce(js.stages, 0)::int,
	ST_AsGeoJSON(ST_Multi(ST_Simplify(ST_Force2D(coalesce(r.shown_geom, js.geom)), $10::float8)), 5),
	o.nr, o.kind
FROM top
LEFT JOIN routes r ON top.kind = 'route' AND r.id = top.id
LEFT JOIN journeys j ON top.kind = 'journey' AND j.id = top.id
JOIN users u ON u.id = coalesce(r.owner_id, j.owner_id)
LEFT JOIN official o ON o.route_id = r.id OR o.journey_id = j.id
LEFT JOIN LATERAL (
	SELECT count(st.id) AS stages, sum(sr.distance_m) AS distance_m, sum(sr.ascent_m) AS ascent_m,
		sum(sr.duration_s) AS duration_s, max(sr.duration_s) AS longest_s, max(sr.sac_grade) AS sac_grade,
		max(sr.sac_max) AS sac_max, ST_Collect(sr.geom) AS geom
	FROM stages st LEFT JOIN routes sr ON sr.id = st.route_id
	WHERE st.journey_id = j.id
) js ON top.kind = 'journey'
ORDER BY top.d, top.id`

// Search returns public routes and journeys that cross the view, nearest to
// its centre first. more is true when there are further results.
func (s *Store) Search(ctx context.Context, q Query) (items []Item, more bool, err error) {
	limit := q.Limit
	if limit <= 0 || limit > MaxLimit {
		limit = MaxLimit
	}
	maxS := q.MaxDurationS
	if maxS <= 0 {
		maxS = math.MaxInt32
	}
	// Simplify to about a pixel of a 1000 px wide map.
	tolerance := math.Min(math.Max((q.East-q.West)/1000, 0.00005), 0.002)
	rows, err := s.DB.Query(ctx, searchSQL, q.West, q.South, q.East, q.North, q.Kind, q.SACMax,
		q.MinDurationS, maxS, limit+1, tolerance, (q.West+q.East)/2, (q.South+q.North)/2, q.Official)
	if err != nil {
		return nil, false, fmt.Errorf("discover: search: %w", err)
	}
	defer rows.Close()
	items = []Item{}
	for rows.Next() {
		var it Item
		var id uuid.UUID
		var line, nr, kind *string
		if err := rows.Scan(&it.Kind, &id, &it.Title, &it.OwnerUsername, &it.DistanceM, &it.AscentM, &it.DurationS,
			&it.LongestS, &it.SACGrade, &it.SACMax, &it.Stages, &line, &nr, &kind); err != nil {
			return nil, false, err
		}
		if nr != nil && kind != nil {
			it.Official = &official.Info{Number: *nr, Kind: *kind}
		}
		it.ID = id.String()
		it.Lines = [][][2]float64{}
		if line != nil {
			var g struct {
				Coordinates [][][2]float64 `json:"coordinates"`
			}
			if err := json.Unmarshal([]byte(*line), &g); err != nil {
				return nil, false, fmt.Errorf("discover: line: %w", err)
			}
			it.Lines = g.Coordinates
		}
		items = append(items, it)
	}
	if len(items) > limit {
		return items[:limit], true, rows.Err()
	}
	return items, false, rows.Err()
}

// ErrNotFound means there is no such public profile.
var ErrNotFound = errors.New("discover: not found")

// User is the public part of an account.
type User struct {
	ID          uuid.UUID
	Username    string
	DisplayName string
	Since       time.Time // month the account was created
	Public      bool      // the profile: found by the search, seen by all
	ShareHikes  bool      // friends see the user's hikes
}

// User looks up an account that is not banned.
func (s *Store) User(ctx context.Context, username string) (User, error) {
	var u User
	err := s.DB.QueryRow(ctx, `SELECT id, username, display_name, date_trunc('month', created_at), profile_public, share_hikes
		FROM users WHERE username = $1 AND banned_at IS NULL`, username).Scan(&u.ID, &u.Username, &u.DisplayName, &u.Since, &u.Public, &u.ShareHikes)
	if errors.Is(err, pgx.ErrNoRows) {
		return u, ErrNotFound
	}
	return u, err
}

// maxProfileLines bounds the routes drawn on a profile's preview image.
const maxProfileLines = 100

// ProfileLines returns the (lon, lat) lines of a user's public routes and of
// the stages of their public journeys as others see them, the most recently
// changed first, simplified for a map of all Switzerland.
func (s *Store) ProfileLines(ctx context.Context, user uuid.UUID) ([][][2]float64, error) {
	rows, err := s.DB.Query(ctx, `SELECT ST_AsGeoJSON(ST_Multi(ST_Simplify(ST_Force2D(r.shown_geom), 0.0005)), 5)
		FROM routes r LEFT JOIN journeys j ON j.id = r.journey_id
		WHERE r.owner_id = $1 AND r.shown_geom IS NOT NULL
			AND CASE WHEN r.journey_id IS NULL THEN r.visibility = 'public' ELSE j.visibility = 'public' END
		ORDER BY coalesce(j.updated_at, r.updated_at) DESC, r.id LIMIT $2`, user, maxProfileLines)
	if err != nil {
		return nil, fmt.Errorf("discover: profile lines: %w", err)
	}
	defer rows.Close()
	var out [][][2]float64
	for rows.Next() {
		var line string
		if err := rows.Scan(&line); err != nil {
			return nil, err
		}
		var g struct {
			Coordinates [][][2]float64 `json:"coordinates"`
		}
		if err := json.Unmarshal([]byte(line), &g); err != nil {
			return nil, fmt.Errorf("discover: profile lines: %w", err)
		}
		out = append(out, g.Coordinates...)
	}
	return out, rows.Err()
}

// ProfileOutlines returns the (lon, lat) lines of the routes and journeys
// listed on a profile by the item's id (a journey's of all its stages), as
// others see them, simplified for a thumbnail.
func (s *Store) ProfileOutlines(ctx context.Context, routeIDs, journeyIDs []uuid.UUID) (map[string][][][2]float64, error) {
	rows, err := s.DB.Query(ctx, `SELECT coalesce(r.journey_id, r.id)::text,
			ST_AsGeoJSON(ST_Multi(ST_Simplify(ST_Force2D(r.shown_geom), 0.0002)), 5)
		FROM routes r
		WHERE (r.id = ANY($1) OR r.journey_id = ANY($2)) AND r.shown_geom IS NOT NULL`, routeIDs, journeyIDs)
	if err != nil {
		return nil, fmt.Errorf("discover: profile outlines: %w", err)
	}
	defer rows.Close()
	out := map[string][][][2]float64{}
	for rows.Next() {
		var id, line string
		if err := rows.Scan(&id, &line); err != nil {
			return nil, err
		}
		var g struct {
			Coordinates [][][2]float64 `json:"coordinates"`
		}
		if err := json.Unmarshal([]byte(line), &g); err != nil {
			return nil, fmt.Errorf("discover: profile outlines: %w", err)
		}
		out[id] = append(out[id], g.Coordinates...)
	}
	return out, rows.Err()
}

// SitemapEntry is a public page for search engines.
type SitemapEntry struct {
	Kind      string    `json:"kind" enum:"route,journey,collection,profile"`
	ID        string    `json:"id" doc:"The item's id; for profiles the username"`
	UpdatedAt time.Time `json:"updated_at"`
}

// MaxSitemap is the most entries listed: a sitemap file holds 50000
// addresses, and each page is there in four languages.
const MaxSitemap = 12500

// Sitemap lists the public routes, journeys and collections of users who
// are not banned, and the profiles of those who published a route or
// journey, the most recently changed first.
func (s *Store) Sitemap(ctx context.Context) ([]SitemapEntry, error) {
	rows, err := s.DB.Query(ctx, `
WITH items AS (
	SELECT 'route' AS kind, r.id::text AS id, r.owner_id, r.updated_at
	FROM routes r WHERE r.visibility = 'public' AND r.journey_id IS NULL
	UNION ALL
	SELECT 'journey', j.id::text, j.owner_id, j.updated_at
	FROM journeys j WHERE j.visibility = 'public'
	UNION ALL
	SELECT 'collection', c.id::text, c.owner_id, c.updated_at
	FROM collections c WHERE c.visibility = 'public'
), shown AS (
	SELECT i.* FROM items i JOIN users u ON u.id = i.owner_id AND u.banned_at IS NULL
)
SELECT kind, id, updated_at FROM shown
UNION ALL
SELECT 'profile', u.username, max(s.updated_at)
FROM shown s JOIN users u ON u.id = s.owner_id
WHERE s.kind <> 'collection'
GROUP BY u.username
ORDER BY 3 DESC
LIMIT $1`, MaxSitemap)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[SitemapEntry])
}
