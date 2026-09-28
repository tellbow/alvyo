// Package travel keeps a user's homes and, per journey, how they get from a
// home to its first stage and back from its last by public transport. Both
// are the user's own: no one else sees them.
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

// Way is the travel of one direction: from (to the first stage) or to (back
// from the last) a home, leaving after or arriving before a time.
type Way struct {
	HomeID string `json:"home_id" format:"uuid"`
	Time   string `json:"time" pattern:"^([01][0-9]|2[0-3]):[0-5][0-9]$" doc:"HH:MM, Swiss time, on the stage's day"`
	Arrive bool   `json:"arrive" doc:"Arriving before the time instead of leaving after it"`
}

// JourneyTravel is a user's travel for a journey; nil where none is chosen.
type JourneyTravel struct {
	To   *Way `json:"to,omitempty" doc:"From a home to the first stage; none if left out"`
	Back *Way `json:"back,omitempty" doc:"From the last stage to a home; none if left out"`
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

// Of returns a user's travel for a journey.
func (s *Store) Of(ctx context.Context, user, journey uuid.UUID) (JourneyTravel, error) {
	rows, err := s.DB.Query(ctx, `SELECT direction, home_id, at_time, arrive FROM journey_travel
		WHERE user_id = $1 AND journey_id = $2`, user, journey)
	if err != nil {
		return JourneyTravel{}, fmt.Errorf("travel: of: %w", err)
	}
	defer rows.Close()
	var j JourneyTravel
	for rows.Next() {
		var dir string
		var home uuid.UUID
		w := &Way{}
		if err := rows.Scan(&dir, &home, &w.Time, &w.Arrive); err != nil {
			return j, fmt.Errorf("travel: of: %w", err)
		}
		w.HomeID = home.String()
		if dir == "to" {
			j.To = w
		} else {
			j.Back = w
		}
	}
	return j, rows.Err()
}

// Set replaces a user's travel for a journey; the homes must be theirs.
func (s *Store) Set(ctx context.Context, user, journey uuid.UUID, j JourneyTravel) error {
	return pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `DELETE FROM journey_travel WHERE user_id = $1 AND journey_id = $2`, user, journey); err != nil {
			return fmt.Errorf("travel: set: %w", err)
		}
		for dir, w := range map[string]*Way{"to": j.To, "back": j.Back} {
			if w == nil {
				continue
			}
			home, err := uuid.Parse(w.HomeID)
			if err != nil {
				return ErrNotFound
			}
			res, err := tx.Exec(ctx, `INSERT INTO journey_travel (user_id, journey_id, direction, home_id, at_time, arrive)
				SELECT $1, $2, $3, id, $5, $6 FROM homes WHERE id = $4 AND owner_id = $1`,
				user, journey, dir, home, w.Time, w.Arrive)
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
