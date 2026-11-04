package discover

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/google/uuid"
)

// HikedTotals sums up hikes: of one year, or (Year 0) of all.
type HikedTotals struct {
	Year         int     `json:"year,omitempty"`
	Hikes        int     `json:"hikes" doc:"A journey's stages count one by one"`
	DistanceM    float64 `json:"distance_m"`
	AscentM      float64 `json:"ascent_m"`
	TimeS        int     `json:"time_s" doc:"As recorded, otherwise the hiking time at one's pace"`
	LongestM     float64 `json:"longest_m"`
	LongestTitle string  `json:"longest_title"`
	HighestM     float64 `json:"highest_m"`
}

func (t *HikedTotals) add(title string, distanceM, ascentM float64, timeS int, highestM float64) {
	t.Hikes++
	t.DistanceM += distanceM
	t.AscentM += ascentM
	t.TimeS += timeS
	t.HighestM = max(t.HighestM, highestM)
	if distanceM > t.LongestM {
		t.LongestM, t.LongestTitle = distanceM, title
	}
}

// HikedItem is one hike: a recording, a day marked on a route, or a stage.
type HikedItem struct {
	Kind      string         `json:"kind" enum:"route,journey,hike"`
	ID        string         `json:"id" format:"uuid"`
	Title     string         `json:"title"`
	On        string         `json:"on" format:"date"`
	DistanceM float64        `json:"distance_m"`
	AscentM   float64        `json:"ascent_m"`
	TimeS     int            `json:"time_s"`
	Lines     [][][2]float64 `json:"lines"`
}

// Hiked is what a user has hiked.
type Hiked struct {
	Total HikedTotals   `json:"total"`
	Years []HikedTotals `json:"years" doc:"Newest first"`
	Items []HikedItem   `json:"items" doc:"Of the year asked for, newest first"`
}

// hikedSQL lists a user's hikes ($1; $2 their verified address, $3 their pace),
// lines only of year $4 (0: all). A day counts once: a mark or a ticked stage is
// left out when the user recorded that route on that day. What the user can no
// longer see is left out too, and others' recordings lack their start and end
// (a short one has no line left, but still counts).
const hikedSQL = `
WITH granted AS (
	SELECT route_id, journey_id, role FROM grants WHERE user_id = $1 OR (email = $2 AND $2 <> '')
), recorded AS (
	SELECT planned_route_id AS route_id, (hiked_at AT TIME ZONE 'Europe/Zurich')::date AS day FROM routes
	WHERE owner_id = $1 AND planned_route_id IS NOT NULL AND hiked_at IS NOT NULL
), hikes AS (
	SELECT 'hike' AS kind, r.id, r.title, (r.hiked_at AT TIME ZONE 'Europe/Zurich')::date AS day, r.geom AS line,
		r.distance_m::float8 AS distance_m, r.ascent_m::float8 AS ascent_m,
		coalesce(nullif(r.hiked_s, 0), round(r.duration_s * $3::float8))::int AS time_s
	FROM routes r
	WHERE r.owner_id = $1 AND r.hiked_at IS NOT NULL AND r.journey_id IS NULL
	UNION ALL
	SELECT CASE WHEN r.hiked_at IS NULL THEN 'route' ELSE 'hike' END, r.id, r.title, d.done_on,
		CASE WHEN r.owner_id = $1 THEN r.geom ELSE r.shown_geom END,
		r.distance_m::float8, r.ascent_m::float8, round(r.duration_s * $3::float8)::int
	FROM done_marks d JOIN routes r ON r.id = d.route_id
	WHERE d.user_id = $1 AND r.journey_id IS NULL
		AND (r.owner_id = $1 OR r.visibility <> 'private' OR r.id IN (SELECT route_id FROM granted))
		AND NOT (r.owner_id = $1 AND (r.hiked_at AT TIME ZONE 'Europe/Zurich')::date IS NOT DISTINCT FROM d.done_on)
		AND NOT EXISTS (SELECT 1 FROM recorded h WHERE h.route_id = r.id AND h.day = d.done_on)
	UNION ALL
	-- Stages ticked off, for the journey's owner and editors.
	SELECT 'journey', j.id, j.title, coalesce(st.done_on, st.updated_at::date),
		CASE WHEN sr.owner_id = $1 THEN sr.geom ELSE sr.shown_geom END,
		sr.distance_m::float8, sr.ascent_m::float8, round(sr.duration_s * $3::float8)::int
	FROM stages st JOIN journeys j ON j.id = st.journey_id JOIN routes sr ON sr.id = st.route_id
	WHERE st.status = 'done'
		AND (j.owner_id = $1 OR j.id IN (SELECT journey_id FROM granted WHERE role = 'editor'))
		AND NOT EXISTS (SELECT 1 FROM recorded h WHERE h.route_id = sr.id AND h.day = coalesce(st.done_on, st.updated_at::date))
	UNION ALL
	-- A mark on a journey counts its stages. Who ticks them off: not the skipped
	-- ones; and the first mark on a journey still under way only adds the
	-- stages not ticked off. Any other mark is the journey hiked again.
	SELECT 'journey', j.id, j.title, d.done_on,
		CASE WHEN sr.owner_id = $1 THEN sr.geom ELSE sr.shown_geom END,
		sr.distance_m::float8, sr.ascent_m::float8, round(sr.duration_s * $3::float8)::int
	FROM done_marks d JOIN journeys j ON j.id = d.journey_id
	JOIN stages st ON st.journey_id = j.id JOIN routes sr ON sr.id = st.route_id
	CROSS JOIN LATERAL (SELECT j.owner_id = $1 OR j.id IN (SELECT journey_id FROM granted WHERE role = 'editor') AS ticks) e
	WHERE d.user_id = $1
		AND (j.owner_id = $1 OR j.visibility <> 'private' OR j.id IN (SELECT journey_id FROM granted))
		AND NOT (e.ticks AND st.status = 'skipped')
		AND NOT (e.ticks AND st.status = 'done'
			AND EXISTS (SELECT 1 FROM stages o WHERE o.journey_id = j.id AND o.status = 'planned')
			AND d.done_on = (SELECT min(f.done_on) FROM done_marks f WHERE f.user_id = $1 AND f.journey_id = j.id))
)
SELECT kind, id, title, to_char(day, 'YYYY-MM-DD'), distance_m, ascent_m, time_s, coalesce(ST_ZMax(line), 0),
	CASE WHEN $4 = 0 OR extract(year FROM day)::int = $4
		THEN ST_AsGeoJSON(ST_Multi(ST_Simplify(ST_Force2D(line), 0.00005)), 5) END
FROM hikes
ORDER BY day DESC, id`

// Hiked returns the user's hikes with their totals, the items of year (0: all).
func (s *Store) Hiked(ctx context.Context, user uuid.UUID, email string, pace float64, year int) (Hiked, error) {
	out := Hiked{Years: []HikedTotals{}, Items: []HikedItem{}}
	rows, err := s.DB.Query(ctx, hikedSQL, user, email, pace, year)
	if err != nil {
		return out, fmt.Errorf("discover: hiked: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var it HikedItem
		var id uuid.UUID
		var highest float64
		var line *string
		if err := rows.Scan(&it.Kind, &id, &it.Title, &it.On, &it.DistanceM, &it.AscentM, &it.TimeS, &highest, &line); err != nil {
			return out, fmt.Errorf("discover: hiked: %w", err)
		}
		y, err := strconv.Atoi(it.On[:4])
		if err != nil {
			return out, fmt.Errorf("discover: hiked: %w", err)
		}
		// Newest first, so a new year is always the next one.
		if n := len(out.Years); n == 0 || out.Years[n-1].Year != y {
			out.Years = append(out.Years, HikedTotals{Year: y})
		}
		out.Years[len(out.Years)-1].add(it.Title, it.DistanceM, it.AscentM, it.TimeS, highest)
		out.Total.add(it.Title, it.DistanceM, it.AscentM, it.TimeS, highest)
		if year != 0 && y != year {
			continue
		}
		it.ID, it.Lines = id.String(), [][][2]float64{}
		if line != nil {
			var g struct {
				Coordinates [][][2]float64 `json:"coordinates"`
			}
			if err := json.Unmarshal([]byte(*line), &g); err != nil {
				return out, fmt.Errorf("discover: hiked line: %w", err)
			}
			it.Lines = g.Coordinates
		}
		out.Items = append(out.Items, it)
	}
	return out, rows.Err()
}
