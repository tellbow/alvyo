// Package done keeps which routes and journeys a user hiked: marked by
// them, or known from their recorded hikes and ticked-off stages
// (route_done_on and journey_done_on in the database).
package done

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Kind is what is marked.
type Kind string

// What can be marked as hiked.
const (
	Route   Kind = "route"
	Journey Kind = "journey"
)

// Store keeps the marks.
type Store struct {
	DB *pgxpool.Pool
}

// State is when the viewer hiked an item, if they did.
type State struct {
	On     *time.Time // nil: not hiked
	Marked bool       // by the viewer's own mark, which can be taken back
}

// Mark records that user hiked the item on day.
func (s *Store) Mark(ctx context.Context, user uuid.UUID, k Kind, id uuid.UUID, day time.Time) error {
	_, err := s.DB.Exec(ctx, `INSERT INTO done_marks (user_id, `+string(k)+`_id, done_on) VALUES ($1, $2, $3)
		ON CONFLICT ON CONSTRAINT done_marks_key DO UPDATE SET done_on = excluded.done_on`, user, id, day)
	return err
}

// Unmark takes user's mark back; a recorded hike still counts.
func (s *Store) Unmark(ctx context.Context, user uuid.UUID, k Kind, id uuid.UUID) error {
	_, err := s.DB.Exec(ctx, `DELETE FROM done_marks WHERE user_id = $1 AND `+string(k)+`_id = $2`, user, id)
	return err
}

// Of returns when viewer hiked the item (viewer may be uuid.Nil: never).
func (s *Store) Of(ctx context.Context, viewer uuid.UUID, k Kind, id uuid.UUID) (State, error) {
	var st State
	q := `SELECT route_done_on(r, $1), EXISTS (SELECT 1 FROM done_marks WHERE user_id = $1 AND route_id = r.id)
		FROM routes r WHERE r.id = $2`
	if k == Journey {
		q = `SELECT journey_done_on($2, $1), EXISTS (SELECT 1 FROM done_marks WHERE user_id = $1 AND journey_id = $2)`
	}
	err := s.DB.QueryRow(ctx, q, viewer, id).Scan(&st.On, &st.Marked)
	if errors.Is(err, pgx.ErrNoRows) {
		return State{}, nil
	}
	return st, err
}

// Days returns when viewer hiked those of the items they hiked.
func (s *Store) Days(ctx context.Context, viewer uuid.UUID, k Kind, ids []uuid.UUID) (map[uuid.UUID]time.Time, error) {
	q := `SELECT r.id, route_done_on(r, $1) FROM routes r WHERE r.id = ANY($2)`
	if k == Journey {
		q = `SELECT id, journey_done_on(id, $1) FROM unnest($2::uuid[]) AS id`
	}
	rows, err := s.DB.Query(ctx, q, viewer, ids)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[uuid.UUID]time.Time{}
	for rows.Next() {
		var id uuid.UUID
		var day *time.Time
		if err := rows.Scan(&id, &day); err != nil {
			return nil, err
		}
		if day != nil {
			out[id] = *day
		}
	}
	return out, rows.Err()
}
