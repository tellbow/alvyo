package community

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"

	"github.com/tellbow/odysgeh/api/internal/dbq"
)

// Relation is how the viewer relates to another user.
type Relation struct {
	Followers int  `json:"followers"`
	Following int  `json:"following"`
	Followed  bool `json:"followed" doc:"The viewer follows this user"`
	Blocked   bool `json:"blocked" doc:"The viewer blocked this user"`
}

// Relation returns other's follower counts and viewer's follow and block of
// them (viewer may be uuid.Nil).
func (s *Store) Relation(ctx context.Context, viewer, other uuid.UUID) (Relation, error) {
	var r Relation
	err := s.DB.QueryRow(ctx, `SELECT
		(SELECT count(*) FROM follows f JOIN users u ON u.id = f.follower_id AND u.banned_at IS NULL WHERE f.followed_id = $2),
		(SELECT count(*) FROM follows f JOIN users u ON u.id = f.followed_id AND u.banned_at IS NULL WHERE f.follower_id = $2),
		EXISTS (SELECT 1 FROM follows WHERE follower_id = $1 AND followed_id = $2),
		EXISTS (SELECT 1 FROM blocks WHERE blocker_id = $1 AND blocked_id = $2)`, viewer, other).
		Scan(&r.Followers, &r.Following, &r.Followed, &r.Blocked)
	return r, err
}

// Follow makes follower follow the user with id followed and tells them.
func (s *Store) Follow(ctx context.Context, follower dbq.User, followed uuid.UUID) error {
	if follower.ID == followed {
		return ErrForbidden
	}
	tag, err := s.DB.Exec(ctx, `INSERT INTO follows (follower_id, followed_id)
		SELECT $1, $2 WHERE NOT EXISTS (SELECT 1 FROM blocks
			WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1))
		ON CONFLICT DO NOTHING`, follower.ID, followed)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		var blocked bool
		if err := s.DB.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM blocks
			WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1))`,
			follower.ID, followed).Scan(&blocked); err != nil {
			return err
		}
		if blocked {
			return ErrBlocked
		}
		return nil // followed before
	}
	s.notifyFollow(ctx, follower, followed)
	return nil
}

// Unfollow ends follower's following of followed.
func (s *Store) Unfollow(ctx context.Context, follower, followed uuid.UUID) error {
	_, err := s.DB.Exec(ctx, `DELETE FROM follows WHERE follower_id = $1 AND followed_id = $2`, follower, followed)
	return err
}

// Block blocks a user; follows between the two end.
func (s *Store) Block(ctx context.Context, blocker, blocked uuid.UUID) error {
	if blocker == blocked {
		return ErrForbidden
	}
	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if _, err := tx.Exec(ctx, `INSERT INTO blocks (blocker_id, blocked_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`, blocker, blocked); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `DELETE FROM follows WHERE (follower_id = $1 AND followed_id = $2)
		OR (follower_id = $2 AND followed_id = $1)`, blocker, blocked); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// Unblock lifts a block.
func (s *Store) Unblock(ctx context.Context, blocker, blocked uuid.UUID) error {
	_, err := s.DB.Exec(ctx, `DELETE FROM blocks WHERE blocker_id = $1 AND blocked_id = $2`, blocker, blocked)
	return err
}

// UserRef names a user.
type UserRef struct {
	Username    string `json:"username"`
	DisplayName string `json:"display_name"`
}

// Blocked lists the users blocker blocked, most recent first.
func (s *Store) Blocked(ctx context.Context, blocker uuid.UUID) ([]UserRef, error) {
	rows, err := s.DB.Query(ctx, `SELECT u.username, u.display_name FROM blocks b JOIN users u ON u.id = b.blocked_id
		WHERE b.blocker_id = $1 ORDER BY b.created_at DESC`, blocker)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []UserRef{}
	for rows.Next() {
		var u UserRef
		if err := rows.Scan(&u.Username, &u.DisplayName); err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

// FeedItem is a route or journey someone the user follows published.
type FeedItem struct {
	Kind          string    `json:"kind" enum:"route,journey"`
	ID            string    `json:"id" format:"uuid"`
	Title         string    `json:"title"`
	OwnerUsername string    `json:"owner_username"`
	OwnerName     string    `json:"owner_name"`
	PublishedAt   time.Time `json:"published_at"`
	DistanceM     float64   `json:"distance_m"`
	AscentM       float64   `json:"ascent_m"`
	DurationS     int       `json:"duration_s"`
	SACGrade      int       `json:"sac_grade"`
	SACMax        int       `json:"sac_max"`
	Stages        int       `json:"stages" doc:"Journeys only"`
}

// Feed returns what the people user follows published before before,
// newest first.
func (s *Store) Feed(ctx context.Context, user uuid.UUID, before time.Time, limit int) ([]FeedItem, error) {
	rows, err := s.DB.Query(ctx, `SELECT * FROM (
		SELECT 'route' AS kind, r.id, r.title, u.username, u.display_name, r.published_at,
			r.distance_m::float8, r.ascent_m::float8, r.duration_s, r.sac_grade::int, r.sac_max::int, 0
		FROM follows f
		JOIN users u ON u.id = f.followed_id AND u.banned_at IS NULL
		JOIN routes r ON r.owner_id = f.followed_id AND r.visibility = 'public' AND r.journey_id IS NULL
		WHERE f.follower_id = $1 AND r.published_at < $2
		UNION ALL
		SELECT 'journey', j.id, j.title, u.username, u.display_name, j.published_at,
			js.distance_m, js.ascent_m, js.duration_s, js.sac_grade, js.sac_max, js.stages
		FROM follows f
		JOIN users u ON u.id = f.followed_id AND u.banned_at IS NULL
		JOIN journeys j ON j.owner_id = f.followed_id AND j.visibility = 'public'
		CROSS JOIN LATERAL (
			SELECT count(st.id)::int AS stages, coalesce(sum(sr.distance_m), 0)::float8 AS distance_m,
				coalesce(sum(sr.ascent_m), 0)::float8 AS ascent_m, coalesce(sum(sr.duration_s), 0)::int AS duration_s,
				coalesce(max(sr.sac_grade), 0)::int AS sac_grade, coalesce(max(sr.sac_max), 0)::int AS sac_max
			FROM stages st LEFT JOIN routes sr ON sr.id = st.route_id WHERE st.journey_id = j.id
		) js
		WHERE f.follower_id = $1 AND j.published_at < $2
	) feed ORDER BY published_at DESC, id LIMIT $3`, user, before, limit)
	if err != nil {
		return nil, fmt.Errorf("community: feed: %w", err)
	}
	defer rows.Close()
	out := []FeedItem{}
	for rows.Next() {
		var it FeedItem
		var id uuid.UUID
		if err := rows.Scan(&it.Kind, &id, &it.Title, &it.OwnerUsername, &it.OwnerName, &it.PublishedAt,
			&it.DistanceM, &it.AscentM, &it.DurationS, &it.SACGrade, &it.SACMax, &it.Stages); err != nil {
			return nil, err
		}
		it.ID = id.String()
		out = append(out, it)
	}
	return out, rows.Err()
}
