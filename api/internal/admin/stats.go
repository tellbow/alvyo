package admin

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// Totals are counts over all of Alvyo, without the system's own accounts
// (alvyo.invalid) and what they own (the official routes).
type Totals struct {
	Accounts    int `json:"accounts"`
	Active7     int `json:"active_7" doc:"Accounts seen in the last 7 days"`
	Active30    int `json:"active_30" doc:"Accounts seen in the last 30 days"`
	Routes      int `json:"routes" doc:"Planned routes, not stages"`
	Hikes       int `json:"hikes" doc:"Hikes recorded with the app"`
	Journeys    int `json:"journeys"`
	Collections int `json:"collections"`
	Photos      int `json:"photos"`
	Comments    int `json:"comments"`
}

// Week is what was new in a week (from Monday).
type Week struct {
	Start    time.Time `json:"start" format:"date"`
	Accounts int       `json:"accounts"`
	Routes   int       `json:"routes"`
	Hikes    int       `json:"hikes"`
	Journeys int       `json:"journeys"`
	Comments int       `json:"comments"`
}

// Stats are the totals and the last weeks, the newest first.
type Stats struct {
	Totals Totals `json:"totals"`
	Weeks  []Week `json:"weeks"`
}

// Stats counts accounts and tours, in total and for each of the last weeks.
func (s *Store) Stats(ctx context.Context, weeks int) (Stats, error) {
	var st Stats
	t := &st.Totals
	err := s.DB.QueryRow(ctx, `
		-- p: persons, not the system's accounts; seen as in Users (store.go)
		WITH p AS (SELECT id FROM users WHERE email NOT LIKE '%@alvyo.invalid')
		SELECT (SELECT count(*) FROM p),
			(SELECT count(DISTINCT user_id) FROM sessions WHERE user_id IN (SELECT id FROM p) AND coalesce(last_seen_at, created_at) > now() - interval '7 days'),
			(SELECT count(DISTINCT user_id) FROM sessions WHERE user_id IN (SELECT id FROM p) AND coalesce(last_seen_at, created_at) > now() - interval '30 days'),
			(SELECT count(*) FROM routes WHERE owner_id IN (SELECT id FROM p) AND journey_id IS NULL AND hiked_at IS NULL),
			(SELECT count(*) FROM routes WHERE owner_id IN (SELECT id FROM p) AND hiked_at IS NOT NULL),
			(SELECT count(*) FROM journeys WHERE owner_id IN (SELECT id FROM p)),
			(SELECT count(*) FROM collections WHERE owner_id IN (SELECT id FROM p)),
			(SELECT count(*) FROM photos),
			(SELECT count(*) FROM comments)`).
		Scan(&t.Accounts, &t.Active7, &t.Active30, &t.Routes, &t.Hikes, &t.Journeys, &t.Collections, &t.Photos, &t.Comments)
	if err != nil {
		return st, err
	}
	rows, err := s.DB.Query(ctx, `
		WITH p AS (SELECT id FROM users WHERE email NOT LIKE '%@alvyo.invalid'),
		w AS (SELECT generate_series(date_trunc('week', now()) - ($1 - 1) * interval '1 week', date_trunc('week', now()), interval '1 week') AS start)
		SELECT w.start::date,
			(SELECT count(*) FROM users WHERE id IN (SELECT id FROM p) AND date_trunc('week', created_at) = w.start),
			(SELECT count(*) FROM routes WHERE owner_id IN (SELECT id FROM p) AND journey_id IS NULL AND hiked_at IS NULL
				AND date_trunc('week', created_at) = w.start),
			(SELECT count(*) FROM routes WHERE owner_id IN (SELECT id FROM p) AND date_trunc('week', hiked_at) = w.start),
			(SELECT count(*) FROM journeys WHERE owner_id IN (SELECT id FROM p) AND date_trunc('week', created_at) = w.start),
			(SELECT count(*) FROM comments WHERE date_trunc('week', created_at) = w.start)
		FROM w ORDER BY w.start DESC`, weeks)
	if err != nil {
		return st, err
	}
	st.Weeks, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (Week, error) {
		var w Week
		err := r.Scan(&w.Start, &w.Accounts, &w.Routes, &w.Hikes, &w.Journeys, &w.Comments)
		return w, err
	})
	return st, err
}
