package routes

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/tellbow/alvyo/api/internal/routing"
)

// Retrail matches every stored route's legs against the official trail
// network again and stores those that changed, with the route's SAC grade
// (routing.TrailMatcher.Retrail): for routes planned while the network was
// missing. The line is the same, so the version stays and no revision is
// kept. It returns how many routes changed.
func (s *Store) Retrail(ctx context.Context, m *routing.TrailMatcher) (int, error) {
	rows, err := s.DB.Query(ctx, `SELECT id FROM routes ORDER BY id`)
	if err != nil {
		return 0, fmt.Errorf("routes: retrail: %w", err)
	}
	ids, err := pgx.CollectRows(rows, pgx.RowTo[uuid.UUID])
	if err != nil {
		return 0, fmt.Errorf("routes: retrail: %w", err)
	}
	changed := 0
	for _, id := range ids {
		ok, err := s.retrail(ctx, m, id)
		if err != nil {
			return changed, fmt.Errorf("routes: retrail %s: %w", id, err)
		}
		if ok {
			changed++
		}
	}
	return changed, nil
}

// retrail does one route, one at a time: some have tens of thousands of points.
func (s *Store) retrail(ctx context.Context, m *routing.TrailMatcher, id uuid.UUID) (bool, error) {
	var version int
	var raw []byte
	err := s.DB.QueryRow(ctx, `SELECT version, legs FROM routes WHERE id = $1`, id).Scan(&version, &raw)
	if errors.Is(err, pgx.ErrNoRows) { // deleted since the run began
		return false, nil
	}
	if err != nil {
		return false, err
	}
	var legs []routing.Leg
	if err := json.Unmarshal(raw, &legs); err != nil {
		return false, err
	}
	retrailed := false
	var t Totals
	for i, l := range legs {
		next, changed, err := m.Retrail(ctx, l)
		if err != nil {
			return false, err
		}
		if changed {
			legs[i], retrailed = next, true
		}
		t.SACGrade = max(t.SACGrade, legs[i].SAC.Grade)
		t.SACMax = max(t.SACMax, legs[i].SAC.Max, legs[i].SAC.Grade)
	}
	if !retrailed {
		return false, nil
	}
	raw, err = json.Marshal(legs)
	if err != nil {
		return false, err
	}
	// Changed meanwhile: left for the next run.
	res, err := s.DB.Exec(ctx, `UPDATE routes SET legs = $3, sac_grade = $4, sac_max = $5 WHERE id = $1 AND version = $2`,
		id, version, raw, t.SACGrade, t.SACMax)
	return err == nil && res.RowsAffected() == 1, err
}
