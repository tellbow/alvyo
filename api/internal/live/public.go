package live

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// Position is where the hiker was, and when.
type Position struct {
	Lon float64   `json:"lon"`
	Lat float64   `json:"lat"`
	At  time.Time `json:"at"`
}

// View is what the link shows: nothing of the hiker but the name and this
// hike.
type View struct {
	Title       string     `json:"title"`
	Hiker       string     `json:"hiker" doc:"The hiker's display name"`
	StartedAt   time.Time  `json:"started_at"`
	ExpectedEnd time.Time  `json:"expected_end"`
	EndedAt     *time.Time `json:"ended_at"`
	Overdue     bool       `json:"overdue" doc:"Not ended 30 minutes after the expected end"`
	Last        *Position  `json:"last"`
	// Way is one position per 5 minutes, oldest first.
	Way []Position `json:"way"`
	// Route is the planned line (lon, lat), simplified; none without a route.
	Route [][2]float64 `json:"route"`
}

// Public returns the view of the link with token, while it works.
func (s *Store) Public(ctx context.Context, token string) (View, error) {
	var v View
	var id uuid.UUID
	var lon, lat *float64
	var lastAt *time.Time
	var route *string
	err := s.DB.QueryRow(ctx, `SELECT l.id, l.title, u.display_name, l.started_at, l.expected_end, l.ended_at,
			l.last_lon, l.last_lat, l.last_at, ST_AsGeoJSON(ST_Simplify(ST_Force2D(
				-- someone else's recorded hike without its first and last 500 m
				CASE WHEN r.hiked_at IS NULL OR r.owner_id = l.owner_id THEN r.geom ELSE shown_line(r.geom) END), 0.0001), 5)
		FROM live_shares l JOIN users u ON u.id = l.owner_id LEFT JOIN routes r ON r.id = l.route_id
		WHERE l.token = $1 AND (l.ended_at IS NULL OR l.ended_at > $2)`, token, s.now().Add(-LinkFor)).
		Scan(&id, &v.Title, &v.Hiker, &v.StartedAt, &v.ExpectedEnd, &v.EndedAt, &lon, &lat, &lastAt, &route)
	if errors.Is(err, pgx.ErrNoRows) {
		return v, ErrNotFound
	}
	if err != nil {
		return v, fmt.Errorf("live: public: %w", err)
	}
	v.Overdue = v.EndedAt == nil && !s.now().Before(v.ExpectedEnd.Add(Grace)) // as Check counts it
	if lon != nil && lat != nil && lastAt != nil {
		v.Last = &Position{Lon: *lon, Lat: *lat, At: *lastAt}
	}
	v.Route = [][2]float64{}
	if route != nil {
		var g struct {
			Coordinates [][2]float64 `json:"coordinates"`
		}
		if err := json.Unmarshal([]byte(*route), &g); err == nil {
			v.Route = g.Coordinates
		}
	}
	rows, err := s.DB.Query(ctx, `SELECT lon, lat, at FROM live_positions WHERE share_id = $1 ORDER BY at`, id)
	if err != nil {
		return v, err
	}
	v.Way, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (Position, error) {
		var p Position
		err := r.Scan(&p.Lon, &p.Lat, &p.At)
		return p, err
	})
	return v, err
}

// Check alerts the contacts of hikes overdue by Grace (once each; again on
// the next check when a mail could not be sent) and deletes shares KeepFor
// after their end.
func (s *Store) Check(ctx context.Context) error {
	now := s.now()
	rows, err := s.DB.Query(ctx, `UPDATE live_shares l SET alerted_at = $1
		FROM users u
		WHERE u.id = l.owner_id AND l.ended_at IS NULL AND l.alerted_at IS NULL AND l.expected_end <= $2
		RETURNING l.id, l.title, l.token, l.expected_end, l.last_lon, l.last_lat, l.last_at,
			u.id, u.display_name, u.email, u.locale`, now, now.Add(-Grace))
	if err != nil {
		return fmt.Errorf("live: overdue: %w", err)
	}
	type overdue struct {
		id           uuid.UUID
		title, token string
		end          time.Time
		lon, lat     *float64
		lastAt       *time.Time
		h            Hiker
	}
	due, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (overdue, error) {
		var o overdue
		err := r.Scan(&o.id, &o.title, &o.token, &o.end, &o.lon, &o.lat, &o.lastAt,
			&o.h.ID, &o.h.DisplayName, &o.h.Email, &o.h.Locale)
		return o, err
	})
	if err != nil {
		return err
	}
	for _, o := range due {
		var last *Position
		if o.lon != nil && o.lat != nil && o.lastAt != nil {
			last = &Position{Lon: *o.lon, Lat: *o.lat, At: *o.lastAt}
		}
		rs, err := s.recipients(ctx, o.id)
		for _, c := range rs {
			if e := s.Mail.Send(ctx, overdueMail(o.h, c.Name, o.title, o.end, last, s.link(o.token), c.Email)); e != nil {
				err = e
			}
		}
		if err != nil {
			// A contact twice is better than none: the alert may be all
			// that tells them someone needs help.
			slog.ErrorContext(ctx, "live: overdue alert, again on the next check", "share", o.id, "err", err)
			if _, err := s.DB.Exec(ctx, `UPDATE live_shares SET alerted_at = NULL WHERE id = $1`, o.id); err != nil {
				return fmt.Errorf("live: overdue again: %w", err)
			}
			continue
		}
		s.send(ctx, overdueSelfMail(o.h, o.title, o.end, s.link(o.token)))
		slog.InfoContext(ctx, "live: overdue alert", "share", o.id, "recipients", len(rs))
	}
	_, err = s.DB.Exec(ctx, `DELETE FROM live_shares
		WHERE coalesce(ended_at, expected_end) < $1`, now.Add(-KeepFor))
	return err
}

// CheckEvery runs Check until ctx ends.
func (s *Store) CheckEvery(ctx context.Context, every time.Duration) {
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		if err := s.Check(ctx); err != nil && ctx.Err() == nil {
			slog.ErrorContext(ctx, "live check", "err", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}
