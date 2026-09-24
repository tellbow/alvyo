// Package tags handles the labels users put on their routes, journeys and
// collections («Winter», «mit Kindern»): kept as typed, compared without
// case.
package tags

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Limits per item.
const (
	Max    = 20
	MaxLen = 40
)

// ErrInvalid wraps tags beyond the limits.
var ErrInvalid = errors.New("invalid tags")

// Normalize trims the tags and collapses their spaces, drops empty ones and
// repeats (ignoring case, the first spelling wins) and checks the limits.
func Normalize(in []string) ([]string, error) {
	out := []string{}
	seen := map[string]bool{}
	for _, t := range in {
		t = strings.Join(strings.Fields(t), " ")
		key := strings.ToLower(t)
		if t == "" || seen[key] {
			continue
		}
		if n := len([]rune(t)); n > MaxLen {
			return nil, fmt.Errorf("%w: %q is longer than %d characters", ErrInvalid, t, MaxLen)
		}
		seen[key] = true
		out = append(out, t)
	}
	if len(out) > Max {
		return nil, fmt.Errorf("%w: at most %d tags", ErrInvalid, Max)
	}
	return out, nil
}

// Count is a tag with how many of the user's items carry it.
type Count struct {
	Tag   string `json:"tag" doc:"The spelling used most"`
	Count int    `json:"count"`
}

// Store reads tags across routes, journeys and collections.
type Store struct {
	DB *pgxpool.Pool
}

// Counts lists the tags on a user's own routes (not journey stages, which use
// their journey's), journeys and collections, most used first.
func (s *Store) Counts(ctx context.Context, owner uuid.UUID) ([]Count, error) {
	rows, err := s.DB.Query(ctx, `
		SELECT mode() WITHIN GROUP (ORDER BY t), count(*)
		FROM (
			SELECT unnest(tags) FROM routes WHERE owner_id = $1 AND journey_id IS NULL
			UNION ALL SELECT unnest(tags) FROM journeys WHERE owner_id = $1
			UNION ALL SELECT unnest(tags) FROM collections WHERE owner_id = $1
		) AS x(t)
		GROUP BY lower(t)
		ORDER BY count(*) DESC, lower(t)`, owner)
	if err != nil {
		return nil, fmt.Errorf("tags: counts: %w", err)
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (Count, error) {
		var c Count
		err := r.Scan(&c.Tag, &c.Count)
		return c, err
	})
}
