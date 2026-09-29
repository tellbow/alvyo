package grants

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/tellbow/alvyo/api/internal/dbq"
)

// Person comes along on a journey: a grant marked along, and the stages
// they are on.
type Person struct {
	ID string `json:"id" format:"uuid" doc:"The grant"`
	// Username and DisplayName of the account, also of one signed in with
	// the invited address; empty for an invitation not taken up yet.
	Username    string `json:"username,omitempty"`
	DisplayName string `json:"display_name,omitempty"`
	// Email for invitations by address, for the owner only.
	Email  string   `json:"email,omitempty"`
	Stages []string `json:"stages" doc:"The ids of the stages they are on"`
}

// People lists who comes along on a journey, in the order they were added;
// withEmail for the owner.
func (s *Store) People(ctx context.Context, journeyID uuid.UUID, withEmail bool) ([]Person, error) {
	rows, err := s.DB.Query(ctx, `
		SELECT g.id, coalesce(u.username, v.username, ''), coalesce(u.display_name, v.display_name, ''),
			coalesce(g.email::text, ''),
			coalesce(array_agg(sp.stage_id ORDER BY st.position) FILTER (WHERE sp.stage_id IS NOT NULL), '{}')
		FROM grants g
		LEFT JOIN users u ON u.id = g.user_id
		LEFT JOIN users v ON v.email = g.email AND v.email_verified_at IS NOT NULL
		LEFT JOIN stage_people sp ON sp.grant_id = g.id
		LEFT JOIN stages st ON st.id = sp.stage_id
		WHERE g.journey_id = $1 AND g.along
		GROUP BY g.id, u.username, v.username, u.display_name, v.display_name, g.email, g.created_at
		ORDER BY g.created_at`, journeyID)
	if err != nil {
		return nil, fmt.Errorf("grants: people: %w", err)
	}
	defer rows.Close()
	out := []Person{}
	for rows.Next() {
		var p Person
		var id uuid.UUID
		var stages []uuid.UUID
		if err := rows.Scan(&id, &p.Username, &p.DisplayName, &p.Email, &stages); err != nil {
			return nil, err
		}
		p.ID = id.String()
		if !withEmail {
			p.Email = ""
		}
		p.Stages = make([]string, len(stages))
		for i, st := range stages {
			p.Stages[i] = st.String()
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// AddPerson marks someone as coming along on a journey, on the given stages
// (nil: all it has). Someone without access yet becomes a viewer and is
// invited by e-mail; a role they have is kept.
func (s *Store) AddPerson(ctx context.Context, t Target, owner dbq.User, in Invite, stages []uuid.UUID) error {
	g, err := s.grantee(ctx, owner, in)
	if err != nil {
		return err
	}
	var inserted bool
	err = pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, t.ID.String()); err != nil {
			return err
		}
		var n int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM grants WHERE journey_id = $1`, t.ID).Scan(&n); err != nil {
			return err
		}
		var id uuid.UUID
		err := tx.QueryRow(ctx, `
			INSERT INTO grants (journey_id, user_id, email, role, invited_by, along)
			VALUES ($1, $2, $3, 'viewer', $4, true)
			ON CONFLICT ON CONSTRAINT grants_target_grantee_key DO UPDATE SET along = true
			RETURNING id, xmax = 0`, t.ID, g.userID, g.email, owner.ID).Scan(&id, &inserted)
		if err != nil {
			return err
		}
		if inserted && n >= MaxPerItem {
			return ErrTooMany // rolls back
		}
		return setStages(ctx, tx, t.ID, id, stages)
	})
	if err != nil {
		return err
	}
	if inserted {
		s.announce(ctx, g, owner, t, "viewer")
	}
	return nil
}

// SetPersonStages sets the stages someone who comes along is on.
func (s *Store) SetPersonStages(ctx context.Context, journeyID, grantID uuid.UUID, stages []uuid.UUID) error {
	return pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		var along bool
		err := tx.QueryRow(ctx, `SELECT along FROM grants WHERE id = $1 AND journey_id = $2`, grantID, journeyID).Scan(&along)
		if errors.Is(err, pgx.ErrNoRows) || (err == nil && !along) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if stages == nil {
			stages = []uuid.UUID{} // none, not all
		}
		return setStages(ctx, tx, journeyID, grantID, stages)
	})
}

// RemovePerson no longer counts someone as coming along; they keep the
// access they have.
func (s *Store) RemovePerson(ctx context.Context, journeyID, grantID uuid.UUID) error {
	res, err := s.DB.Exec(ctx, `UPDATE grants SET along = false WHERE id = $1 AND journey_id = $2 AND along`,
		grantID, journeyID)
	if err != nil {
		return err
	}
	if res.RowsAffected() == 0 {
		return ErrNotFound
	}
	_, err = s.DB.Exec(ctx, `DELETE FROM stage_people WHERE grant_id = $1`, grantID)
	return err
}

// setStages replaces a person's stages with those of the journey among
// stages; nil means all its stages.
func setStages(ctx context.Context, tx pgx.Tx, journeyID, grantID uuid.UUID, stages []uuid.UUID) error {
	if _, err := tx.Exec(ctx, `DELETE FROM stage_people WHERE grant_id = $1`, grantID); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `
		INSERT INTO stage_people (stage_id, grant_id)
		SELECT id, $2 FROM stages WHERE journey_id = $1 AND ($3::uuid[] IS NULL OR id = ANY($3))`,
		journeyID, grantID, stages)
	return err
}
