package discover

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/google/uuid"
)

// MaxMine is the most items of a user's map one request returns.
const MaxMine = 200

// MineQuery narrows a user's own routes, journeys and recorded hikes in the
// map view. Zero bounds are open.
type MineQuery struct {
	UserID        uuid.UUID
	VerifiedEmail string // "" if unverified: shared by e-mail invitation only then
	West, South   float64
	East, North   float64
	Kinds         []string // route, journey, hike; none for all
	Tags          []string // any of them, without case; none for all
	// Shared adds the routes and journeys others shared with the user.
	Shared                     bool
	MinDistanceM, MaxDistanceM float64
	MinDurationS, MaxDurationS int
	MinSAC, MaxSAC             int
	// LongestStage compares a journey's longest stage instead of the whole
	// journey with the distance and time bounds.
	LongestStage bool
	// Done: "done" only what the user hiked, "planned" only the rest; ""
	// all.
	Done string
}

// MineItem is a route, journey or recorded hike on the user's map.
type MineItem struct {
	Kind          string   `json:"kind" enum:"route,journey,hike"`
	ID            string   `json:"id" format:"uuid"`
	Title         string   `json:"title"`
	OwnerUsername string   `json:"owner_username"`
	Tags          []string `json:"tags"`
	DistanceM     float64  `json:"distance_m" doc:"Journeys: all stages together"`
	AscentM       float64  `json:"ascent_m"`
	DurationS     int      `json:"duration_s" doc:"Journeys: all stages together"`
	LongestM      float64  `json:"longest_m" doc:"Journeys: the longest stage; otherwise as distance_m"`
	LongestS      int      `json:"longest_s" doc:"Journeys: the longest stage; otherwise as duration_s"`
	SACGrade      int      `json:"sac_grade"`
	SACMax        int      `json:"sac_max"`
	Stages        int      `json:"stages" doc:"Journeys only"`
	DoneOn        *string  `json:"done_on,omitempty" format:"date" doc:"When the user hiked it, if they did"`
	// Lines are simplified (lon, lat) lines for the map.
	Lines [][][2]float64 `json:"lines"`
}

// mineSQL: a user has few enough items to filter them all; the nearest to
// the centre of the view ($12, $13) come first.
const mineSQL = `
WITH granted AS (
	SELECT route_id, journey_id FROM grants
	WHERE $3 AND (user_id = $1 OR (email = $2 AND $2 <> ''))
), items AS (
	SELECT CASE WHEN r.hiked_at IS NULL THEN 'route' ELSE 'hike' END AS kind, r.id, r.title, r.owner_id, r.tags,
		r.distance_m::float8 AS distance_m, r.ascent_m::float8 AS ascent_m, r.duration_s,
		r.distance_m::float8 AS longest_m, r.duration_s AS longest_s, r.sac_grade, r.sac_max, 0 AS stages,
		route_done_on(r, $1) AS done_on,
		-- others' recorded hikes without their start and end
		-- (also found and sorted by it: the whole line would give their ends away)
		CASE WHEN r.owner_id = $1 THEN r.geom ELSE r.shown_geom END AS shown
	FROM routes r
	WHERE r.journey_id IS NULL
		AND (r.owner_id = $1 OR r.id IN (SELECT route_id FROM granted))
		AND ST_Intersects(CASE WHEN r.owner_id = $1 THEN r.geom ELSE r.shown_geom END, ST_MakeEnvelope($4, $5, $6, $7, 4326))
	UNION ALL
	SELECT 'journey', j.id, j.title, j.owner_id, j.tags,
		js.distance_m, js.ascent_m, js.duration_s, js.longest_m, js.longest_s, js.sac_grade, js.sac_max, js.stages,
		journey_done_on(j.id, $1),
		js.geom
	FROM journeys j
	CROSS JOIN LATERAL (
		SELECT count(st.id)::int AS stages, sum(sr.distance_m)::float8 AS distance_m, sum(sr.ascent_m)::float8 AS ascent_m,
			sum(sr.duration_s)::int AS duration_s, max(sr.distance_m)::float8 AS longest_m, max(sr.duration_s) AS longest_s,
			max(sr.sac_grade) AS sac_grade, max(sr.sac_max) AS sac_max, ST_Collect(sr.geom) AS geom
		FROM stages st LEFT JOIN routes sr ON sr.id = st.route_id
		WHERE st.journey_id = j.id
	) js
	WHERE (j.owner_id = $1 OR j.id IN (SELECT journey_id FROM granted))
		AND ST_Intersects(js.geom, ST_MakeEnvelope($4, $5, $6, $7, 4326))
)
SELECT i.kind, i.id, i.title, u.username, i.tags, i.distance_m, i.ascent_m, i.duration_s, i.longest_m, i.longest_s,
	i.sac_grade, i.sac_max, i.stages, i.done_on,
	ST_AsGeoJSON(ST_Multi(ST_Simplify(ST_Force2D(i.shown), $11::float8)), 5)
FROM items i JOIN users u ON u.id = i.owner_id
WHERE (cardinality($8::text[]) = 0 OR i.kind = ANY($8))
	AND (cardinality($9::text[]) = 0 OR lower_tags(i.tags) && $9)
	AND CASE WHEN $10 AND i.kind = 'journey' THEN i.longest_m ELSE i.distance_m END BETWEEN $14 AND $15
	AND CASE WHEN $10 AND i.kind = 'journey' THEN i.longest_s ELSE i.duration_s END BETWEEN $16 AND $17
	AND i.sac_grade BETWEEN $18 AND $19
	AND ($21 = '' OR ($21 = 'done') = (i.done_on IS NOT NULL))
ORDER BY i.shown <-> ST_Point($12, $13, 4326), i.id
LIMIT $20`

// Mine returns the user's items in the view that pass the filters, nearest
// to the centre first; more is true when there are further ones.
func (s *Store) Mine(ctx context.Context, q MineQuery) (items []MineItem, more bool, err error) {
	open := func(v, top float64) float64 {
		if v <= 0 {
			return top
		}
		return v
	}
	tags := make([]string, len(q.Tags))
	for i, t := range q.Tags {
		tags[i] = strings.ToLower(t)
	}
	kinds := q.Kinds
	if kinds == nil {
		kinds = []string{}
	}
	tolerance := math.Min(math.Max((q.East-q.West)/1000, 0.00005), 0.002)
	rows, err := s.DB.Query(ctx, mineSQL, q.UserID, q.VerifiedEmail, q.Shared, q.West, q.South, q.East, q.North,
		kinds, tags, q.LongestStage, tolerance, (q.West+q.East)/2, (q.South+q.North)/2,
		q.MinDistanceM, open(q.MaxDistanceM, math.MaxFloat64),
		q.MinDurationS, int(open(float64(q.MaxDurationS), math.MaxInt32)),
		q.MinSAC, int(open(float64(q.MaxSAC), 6)), MaxMine+1, q.Done)
	if err != nil {
		return nil, false, fmt.Errorf("discover: mine: %w", err)
	}
	defer rows.Close()
	items = []MineItem{}
	for rows.Next() {
		var it MineItem
		var id uuid.UUID
		var line *string
		var doneOn *time.Time
		if err := rows.Scan(&it.Kind, &id, &it.Title, &it.OwnerUsername, &it.Tags, &it.DistanceM, &it.AscentM,
			&it.DurationS, &it.LongestM, &it.LongestS, &it.SACGrade, &it.SACMax, &it.Stages, &doneOn, &line); err != nil {
			return nil, false, err
		}
		if doneOn != nil {
			s := doneOn.Format(time.DateOnly)
			it.DoneOn = &s
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
	if len(items) > MaxMine {
		return items[:MaxMine], true, rows.Err()
	}
	return items, false, rows.Err()
}
