package discover

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// HikedTotals sums up hikes: of one year, or (Year 0) of all.
type HikedTotals struct {
	Year      int     `json:"year,omitempty"`
	Hikes     int     `json:"hikes" doc:"A journey's stages count one by one"`
	DistanceM float64 `json:"distance_m"`
	AscentM   float64 `json:"ascent_m"`
	TimeS     int     `json:"time_s" doc:"As recorded, otherwise the hiking time at one's pace"`
	LongestM  float64 `json:"longest_m"`
	HighestM  float64 `json:"highest_m"`
}

func (t *HikedTotals) add(distanceM, ascentM float64, timeS int, highestM float64) {
	t.Hikes++
	t.DistanceM += distanceM
	t.AscentM += ascentM
	t.TimeS += timeS
	t.HighestM = max(t.HighestM, highestM)
	t.LongestM = max(t.LongestM, distanceM)
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

// hikesCTE is the CTE hikes: a user's hikes ($1; $2 their verified address, $3
// their pace). A day counts once: a mark or a ticked stage is left out when the
// user recorded that route on that day. What the user can no longer see is left
// out too, and others' recordings lack their start and end (a short one has no
// line left, but still counts). whole and open are for what the user shares:
// someone else's private route stays out of it.
const hikesCTE = `
WITH granted AS (
	SELECT route_id, journey_id, role FROM grants WHERE user_id = $1 OR (email = $2 AND $2 <> '')
), recorded AS (
	SELECT planned_route_id AS route_id, (hiked_at AT TIME ZONE 'Europe/Zurich')::date AS day FROM routes
	WHERE owner_id = $1 AND planned_route_id IS NOT NULL AND hiked_at IS NOT NULL
), hikes AS (
	SELECT 'hike' AS kind, r.id, r.title, (r.hiked_at AT TIME ZONE 'Europe/Zurich')::date AS day, r.geom AS line, r.geom AS whole, true AS open,
		r.distance_m::float8 AS distance_m, r.ascent_m::float8 AS ascent_m,
		coalesce(nullif(r.hiked_s, 0), round(r.duration_s * $3::float8))::int AS time_s
	FROM routes r
	WHERE r.owner_id = $1 AND r.hiked_at IS NOT NULL AND r.journey_id IS NULL
	UNION ALL
	SELECT CASE WHEN r.hiked_at IS NULL THEN 'route' ELSE 'hike' END, r.id, r.title, d.done_on,
		CASE WHEN r.owner_id = $1 THEN r.geom ELSE r.shown_geom END, r.geom, r.owner_id = $1 OR r.visibility = 'public',
		r.distance_m::float8, r.ascent_m::float8, round(r.duration_s * $3::float8)::int
	FROM done_marks d JOIN routes r ON r.id = d.route_id
	WHERE d.user_id = $1 AND r.journey_id IS NULL
		AND (r.owner_id = $1 OR r.visibility <> 'private' OR r.id IN (SELECT route_id FROM granted))
		AND NOT (r.owner_id = $1 AND (r.hiked_at AT TIME ZONE 'Europe/Zurich')::date IS NOT DISTINCT FROM d.done_on)
		AND NOT EXISTS (SELECT 1 FROM recorded h WHERE h.route_id = r.id AND h.day = d.done_on)
	UNION ALL
	-- Stages ticked off, for the journey's owner and editors.
	SELECT 'journey', j.id, j.title, coalesce(st.done_on, st.updated_at::date),
		CASE WHEN sr.owner_id = $1 THEN sr.geom ELSE sr.shown_geom END, sr.geom, j.owner_id = $1 OR j.visibility = 'public',
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
		CASE WHEN sr.owner_id = $1 THEN sr.geom ELSE sr.shown_geom END, sr.geom, j.owner_id = $1 OR j.visibility = 'public',
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
`

// hikedSQL lists the hikes, with lines only of year $4 (0: all).
const hikedSQL = hikesCTE + `
SELECT kind, id, title, to_char(day, 'YYYY-MM-DD'), distance_m, ascent_m, time_s, coalesce(ST_ZMax(line), 0),
	CASE WHEN $4 = 0 OR extract(year FROM day)::int = $4
		THEN ST_AsGeoJSON(ST_Multi(ST_Simplify(ST_Force2D(line), 0.00005)), 5) END
FROM hikes
ORDER BY day DESC, id`

// NoItems asks Hiked for the totals alone.
const NoItems = -1

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
		out.Years[len(out.Years)-1].add(it.DistanceM, it.AscentM, it.TimeS, highest)
		out.Total.add(it.DistanceM, it.AscentM, it.TimeS, highest)
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

// SharedLines returns the lines of what the user hiked for others to see: no
// titles or dates, in an order that says nothing of when, and all without the
// first and last 500 m, as their ends may be where someone lives.
func (s *Store) SharedLines(ctx context.Context, user uuid.UUID, email string) ([][][2]float64, error) {
	rows, err := s.DB.Query(ctx, hikesCTE+`
SELECT ST_AsGeoJSON(ST_Multi(ST_Simplify(ST_Force2D(shown), 0.00005)), 5)
FROM (SELECT id, day, shown_line(whole) AS shown FROM hikes WHERE open) t
WHERE shown IS NOT NULL
ORDER BY md5(id::text || day::text)`, user, email, 1.0)
	if err != nil {
		return nil, fmt.Errorf("discover: shared lines: %w", err)
	}
	defer rows.Close()
	out := [][][2]float64{}
	for rows.Next() {
		var line string
		if err := rows.Scan(&line); err != nil {
			return nil, fmt.Errorf("discover: shared lines: %w", err)
		}
		var g struct {
			Coordinates [][][2]float64 `json:"coordinates"`
		}
		if err := json.Unmarshal([]byte(line), &g); err != nil {
			return nil, fmt.Errorf("discover: shared lines: %w", err)
		}
		out = append(out, g.Coordinates...)
	}
	return out, rows.Err()
}

// Summit is a summit passed.
type Summit struct {
	Name string `json:"name"`
	Ele  *int32 `json:"ele,omitempty"`
}

// OfficialDone is how many official routes of a kind the user has hiked.
type OfficialDone struct {
	Kind  string `json:"kind" enum:"national,regional,local,handicap"`
	Done  int    `json:"done"`
	Total int    `json:"total"`
}

// Achievements are plain facts about what a user hiked, all years together.
type Achievements struct {
	Cantons      []string       `json:"cantons" doc:"Codes of the cantons walked in, such as BE"`
	CantonsTotal int            `json:"cantons_total"`
	Official     []OfficialDone `json:"official"`
	Summits      []Summit       `json:"summits" doc:"Named summits within 50 m of a hike, the highest first"`
	Huts         []string       `json:"huts" doc:"Huts within 100 m of a hike"`
}

// linesCTE adds to hikesCTE each distinct line once.
const linesCTE = hikesCTE + `, lines AS (SELECT DISTINCT line FROM hikes WHERE line IS NOT NULL)
`

// near is true of a point within so many metres of a line; the first, rough test
// in degrees is the one the index on the points helps with.
func near(point string, metres int) string {
	return fmt.Sprintf(`ST_DWithin(%[1]s, l.line, %[2]f) AND ST_DWithin(%[1]s::geography, ST_Force2D(l.line)::geography, %[3]d)`,
		point, float64(metres)/50000, metres)
}

// Achievements returns what the user has achieved.
func (s *Store) Achievements(ctx context.Context, user uuid.UUID, email string) (Achievements, error) {
	a := Achievements{Cantons: []string{}, CantonsTotal: 26, Official: []OfficialDone{}, Summits: []Summit{}, Huts: []string{}}
	collect := func(q string, scan func(pgx.Rows) error, args ...any) error {
		rows, err := s.DB.Query(ctx, q, args...)
		if err != nil {
			return fmt.Errorf("discover: achievements: %w", err)
		}
		defer rows.Close()
		for rows.Next() {
			if err := scan(rows); err != nil {
				return fmt.Errorf("discover: achievements: %w", err)
			}
		}
		return rows.Err()
	}
	err := collect(linesCTE+`SELECT c.code FROM cantons c WHERE EXISTS (SELECT 1 FROM lines l WHERE ST_Intersects(c.geom, l.line)) ORDER BY c.code`,
		func(r pgx.Rows) error {
			var code string
			err := r.Scan(&code)
			a.Cantons = append(a.Cantons, code)
			return err
		}, user, email, 1.0)
	if err != nil {
		return a, err
	}
	err = collect(linesCTE+`SELECT DISTINCT p.id, p.name, p.ele FROM lines l JOIN pois p ON p.kind = 'peak' AND p.name <> '' AND `+near("p.geom", 50)+`
		ORDER BY p.ele DESC NULLS LAST, p.name, p.id`,
		func(r pgx.Rows) error {
			var id uuid.UUID
			var p Summit
			err := r.Scan(&id, &p.Name, &p.Ele)
			a.Summits = append(a.Summits, p)
			return err
		}, user, email, 1.0)
	if err != nil {
		return a, err
	}
	err = collect(linesCTE+`SELECT DISTINCT p.id, p.name FROM lines l JOIN places p ON p.kind = 'hut' AND `+near("p.geom", 100)+`
		ORDER BY p.name, p.id`,
		func(r pgx.Rows) error {
			var id uuid.UUID
			var name string
			err := r.Scan(&id, &name)
			a.Huts = append(a.Huts, name)
			return err
		}, user, email, 1.0)
	if err != nil {
		return a, err
	}
	// Hiked: marked, or recorded from it; a multi-day route also when each of
	// its stages was recorded.
	err = collect(`SELECT o.kind, count(*) FILTER (WHERE
			EXISTS (SELECT 1 FROM done_marks d WHERE d.user_id = $1 AND (d.route_id = o.route_id OR d.journey_id = o.journey_id))
			OR EXISTS (SELECT 1 FROM routes h WHERE h.owner_id = $1 AND h.hiked_at IS NOT NULL AND h.planned_route_id = o.route_id)
			OR (o.journey_id IS NOT NULL AND EXISTS (SELECT 1 FROM stages st WHERE st.journey_id = o.journey_id AND st.route_id IS NOT NULL)
				AND NOT EXISTS (SELECT 1 FROM stages st WHERE st.journey_id = o.journey_id AND st.route_id IS NOT NULL AND NOT EXISTS (
					SELECT 1 FROM routes h WHERE h.owner_id = $1 AND h.hiked_at IS NOT NULL AND h.planned_route_id = st.route_id)))
		), count(*)
		FROM official o GROUP BY o.kind
		ORDER BY array_position(ARRAY['national', 'regional', 'local', 'handicap'], o.kind)`,
		func(r pgx.Rows) error {
			var o OfficialDone
			err := r.Scan(&o.Kind, &o.Done, &o.Total)
			a.Official = append(a.Official, o)
			return err
		}, user)
	return a, err
}
