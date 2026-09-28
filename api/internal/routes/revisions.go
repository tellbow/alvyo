package routes

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// MaxRevisions is how many earlier versions of a route's line are kept.
const MaxRevisions = 20

// Revision is an earlier version of a route's line.
type Revision struct {
	Version   int       `json:"version" doc:"The route's version it was"`
	SavedAt   time.Time `json:"saved_at"`
	SavedBy   string    `json:"saved_by" doc:"Username of who saved it; empty when that account is gone"`
	DistanceM int       `json:"distance_m"`
	AscentM   int       `json:"ascent_m"`
	DurationS int       `json:"duration_s"`
}

// Revisions lists a route's earlier lines, the newest first.
func (s *Store) Revisions(ctx context.Context, id uuid.UUID) ([]Revision, error) {
	rows, err := s.DB.Query(ctx, `
		SELECT rv.version, rv.saved_at, coalesce(u.username, ''), rv.distance_m, rv.ascent_m, rv.duration_s
		FROM route_revisions rv LEFT JOIN users u ON u.id = rv.saved_by
		WHERE rv.route_id = $1 ORDER BY rv.version DESC`, id)
	if err != nil {
		return nil, fmt.Errorf("routes: revisions: %w", err)
	}
	out, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (Revision, error) {
		var r Revision
		err := row.Scan(&r.Version, &r.SavedAt, &r.SavedBy, &r.DistanceM, &r.AscentM, &r.DurationS)
		return r, err
	})
	if err != nil {
		return nil, fmt.Errorf("routes: revisions: %w", err)
	}
	return out, nil
}

// RevisionContent is the line of a route at an earlier version.
func (s *Store) RevisionContent(ctx context.Context, id uuid.UUID, version int) (Revision, Content, error) {
	var r Revision
	var c Content
	var anchors, legs []byte
	err := s.DB.QueryRow(ctx, `
		SELECT rv.version, rv.saved_at, coalesce(u.username, ''), rv.distance_m, rv.ascent_m, rv.duration_s,
			rv.profile, rv.anchors, rv.legs
		FROM route_revisions rv LEFT JOIN users u ON u.id = rv.saved_by
		WHERE rv.route_id = $1 AND rv.version = $2`, id, version).
		Scan(&r.Version, &r.SavedAt, &r.SavedBy, &r.DistanceM, &r.AscentM, &r.DurationS, &c.Profile, &anchors, &legs)
	if errors.Is(err, pgx.ErrNoRows) {
		return r, c, ErrNotFound
	}
	if err != nil {
		return r, c, fmt.Errorf("routes: revision: %w", err)
	}
	if err := json.Unmarshal(anchors, &c.Anchors); err != nil {
		return r, c, fmt.Errorf("routes: revision anchors: %w", err)
	}
	if err := json.Unmarshal(legs, &c.Legs); err != nil {
		return r, c, fmt.Errorf("routes: revision legs: %w", err)
	}
	return r, c, nil
}
