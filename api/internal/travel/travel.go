// Package travel keeps a user's homes and, per journey and route, how they
// get from a home or another place to the start and back from the end by
// public transport. Both are the user's own: no one else sees them.
package travel

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// MaxHomes per user.
const MaxHomes = 5

// Errors.
var (
	ErrNotFound = errors.New("travel: not found")
	ErrTooMany  = errors.New("travel: too many homes")
)

// Home is where a user sets off from or returns to.
type Home struct {
	ID      string  `json:"id" format:"uuid"`
	Name    string  `json:"name" doc:"e.g. Zuhause, Büro"`
	Address string  `json:"address" doc:"As found by the place search"`
	Lon     float64 `json:"lon"`
	Lat     float64 `json:"lat"`
}

// Way is the travel of one direction: from (to the start) or to (back from
// the end) a home or another place, leaving after or arriving before a time.
type Way struct {
	HomeID string `json:"home_id,omitempty" format:"uuid" doc:"One of one's homes; or place"`
	Place  *Spot  `json:"place,omitempty" doc:"Anywhere else; or home_id"`
	Time   string `json:"time" pattern:"^([01][0-9]|2[0-3]):[0-5][0-9]$" doc:"HH:MM, Swiss time, on the day of the hike"`
	Arrive bool   `json:"arrive" doc:"Arriving before the time instead of leaving after it"`
}

// Spot is where a way starts or ends that is not a home: a place found by
// the search.
type Spot struct {
	Name string  `json:"name" minLength:"1" maxLength:"60"`
	Lon  float64 `json:"lon" minimum:"-180" maximum:"180"`
	Lat  float64 `json:"lat" minimum:"-90" maximum:"90"`
}

// Travel is a user's travel for a journey or a route; nil where none is
// chosen.
type Travel struct {
	To   *Way `json:"to,omitempty" doc:"To the start; none if left out"`
	Back *Way `json:"back,omitempty" doc:"Back from the end; none if left out"`
}

// For is what travel belongs to.
type For int

// A journey (to its first stage and back from its last) or a route.
const (
	Journey For = iota
	Route
)

// table and column of the travel of f.
func (f For) table() (string, string) {
	if f == Route {
		return "route_travel", "route_id"
	}
	return "journey_travel", "journey_id"
}

// Store keeps homes and travel.
type Store struct {
	DB *pgxpool.Pool
}

// Homes lists a user's homes in the order they were added.
func (s *Store) Homes(ctx context.Context, owner uuid.UUID) ([]Home, error) {
	rows, err := s.DB.Query(ctx, `SELECT id, name, address, lon, lat FROM homes WHERE owner_id = $1 ORDER BY created_at, id`, owner)
	if err != nil {
		return nil, fmt.Errorf("travel: homes: %w", err)
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (Home, error) {
		var h Home
		var id uuid.UUID
		err := r.Scan(&id, &h.Name, &h.Address, &h.Lon, &h.Lat)
		h.ID = id.String()
		return h, err
	})
}

// AddHome adds a home, at most MaxHomes. The user's row is locked, so two
// at once cannot both be the fifth.
func (s *Store) AddHome(ctx context.Context, owner uuid.UUID, h Home) (Home, error) {
	err := pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `SELECT 1 FROM users WHERE id = $1 FOR UPDATE`, owner); err != nil {
			return err
		}
		var n int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM homes WHERE owner_id = $1`, owner).Scan(&n); err != nil {
			return err
		}
		if n >= MaxHomes {
			return ErrTooMany
		}
		var id uuid.UUID
		err := tx.QueryRow(ctx, `INSERT INTO homes (owner_id, name, address, lon, lat) VALUES ($1, $2, $3, $4, $5)
			RETURNING id`, owner, h.Name, h.Address, h.Lon, h.Lat).Scan(&id)
		h.ID = id.String()
		return err
	})
	if err != nil && !errors.Is(err, ErrTooMany) {
		return h, fmt.Errorf("travel: add home: %w", err)
	}
	return h, err
}

// DeleteHome removes a home, and the travel from and to it.
func (s *Store) DeleteHome(ctx context.Context, owner, id uuid.UUID) error {
	res, err := s.DB.Exec(ctx, `DELETE FROM homes WHERE id = $1 AND owner_id = $2`, id, owner)
	if err != nil {
		return fmt.Errorf("travel: delete home: %w", err)
	}
	if res.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// Of returns a user's travel for a journey or route.
func (s *Store) Of(ctx context.Context, f For, user, id uuid.UUID) (Travel, error) {
	table, col := f.table()
	rows, err := s.DB.Query(ctx, `SELECT direction, home_id, place_name, place_lon, place_lat, at_time, arrive
		FROM `+table+` WHERE user_id = $1 AND `+col+` = $2`, user, id)
	if err != nil {
		return Travel{}, fmt.Errorf("travel: of: %w", err)
	}
	defer rows.Close()
	var t Travel
	for rows.Next() {
		var dir string
		var home *uuid.UUID
		var name *string
		var lon, lat *float64
		w := &Way{}
		if err := rows.Scan(&dir, &home, &name, &lon, &lat, &w.Time, &w.Arrive); err != nil {
			return t, fmt.Errorf("travel: of: %w", err)
		}
		if home != nil {
			w.HomeID = home.String()
		} else if name != nil && lon != nil && lat != nil {
			w.Place = &Spot{Name: *name, Lon: *lon, Lat: *lat}
		}
		if dir == "to" {
			t.To = w
		} else {
			t.Back = w
		}
	}
	return t, rows.Err()
}

// Set replaces a user's travel for a journey or route; the homes must be
// theirs.
func (s *Store) Set(ctx context.Context, f For, user, id uuid.UUID, t Travel) error {
	table, col := f.table()
	return pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `DELETE FROM `+table+` WHERE user_id = $1 AND `+col+` = $2`, user, id); err != nil {
			return fmt.Errorf("travel: set: %w", err)
		}
		for dir, w := range map[string]*Way{"to": t.To, "back": t.Back} {
			if w == nil {
				continue
			}
			if w.Place != nil {
				if w.HomeID != "" {
					return ErrNotFound
				}
				_, err := tx.Exec(ctx, `INSERT INTO `+table+` (user_id, `+col+`, direction, place_name, place_lon, place_lat, at_time, arrive)
					VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
					user, id, dir, w.Place.Name, w.Place.Lon, w.Place.Lat, w.Time, w.Arrive)
				if err != nil {
					return fmt.Errorf("travel: set: %w", err)
				}
				continue
			}
			home, err := uuid.Parse(w.HomeID)
			if err != nil {
				return ErrNotFound
			}
			res, err := tx.Exec(ctx, `INSERT INTO `+table+` (user_id, `+col+`, direction, home_id, at_time, arrive)
				SELECT $1, $2, $3, id, $5, $6 FROM homes WHERE id = $4 AND owner_id = $1`,
				user, id, dir, home, w.Time, w.Arrive)
			if err != nil {
				return fmt.Errorf("travel: set: %w", err)
			}
			if res.RowsAffected() == 0 {
				return ErrNotFound // not one of the user's homes
			}
		}
		return nil
	})
}
