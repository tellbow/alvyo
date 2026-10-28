package community

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/tellbow/alvyo/api/internal/dbq"
)

// Relation is how the viewer relates to another user.
type Relation struct {
	Followers int    `json:"followers"`
	Following int    `json:"following"`
	Followed  bool   `json:"followed" doc:"The viewer follows this user"`
	Blocked   bool   `json:"blocked" doc:"The viewer blocked this user"`
	Friend    Friend `json:"friend" enum:"none,requested,incoming,friends" doc:"Friends, or who asked whom"`
}

// Relation returns other's follower counts and viewer's follow and block of
// them (viewer may be uuid.Nil).
func (s *Store) Relation(ctx context.Context, viewer, other uuid.UUID) (Relation, error) {
	var r Relation
	err := s.DB.QueryRow(ctx, `SELECT
		(SELECT count(*) FROM follows f JOIN users u ON u.id = f.follower_id AND u.banned_at IS NULL WHERE f.followed_id = $2),
		(SELECT count(*) FROM follows f JOIN users u ON u.id = f.followed_id AND u.banned_at IS NULL WHERE f.follower_id = $2),
		EXISTS (SELECT 1 FROM follows WHERE follower_id = $1 AND followed_id = $2),
		EXISTS (SELECT 1 FROM blocks WHERE blocker_id = $1 AND blocked_id = $2),
		`+friendState, viewer, other).
		Scan(&r.Followers, &r.Following, &r.Followed, &r.Blocked, &r.Friend)
	return r, err
}

// pairTx runs fn in a transaction that holds a lock on the pair a, b: a
// block, a follow and a friend request between the same two go one after
// the other, and each sees what the one before wrote.
func (s *Store) pairTx(ctx context.Context, a, b uuid.UUID, fn func(pgx.Tx) error) error {
	return pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext(least($1::text, $2::text) || greatest($1::text, $2::text)))`,
			a, b); err != nil {
			return err
		}
		return fn(tx)
	})
}

// Follow makes follower follow the user with id followed and tells them.
func (s *Store) Follow(ctx context.Context, follower dbq.User, followed uuid.UUID) error {
	if follower.ID == followed {
		return ErrForbidden
	}
	var added bool
	err := s.pairTx(ctx, follower.ID, followed, func(tx pgx.Tx) error {
		if err := notBlocked(ctx, tx, follower.ID, followed); err != nil {
			return err
		}
		tag, err := tx.Exec(ctx, `INSERT INTO follows (follower_id, followed_id) VALUES ($1, $2)
			ON CONFLICT DO NOTHING`, follower.ID, followed)
		added = tag.RowsAffected() > 0 // or followed before
		return err
	})
	if err != nil || !added {
		return err
	}
	s.notifyFollow(ctx, follower, followed)
	return nil
}

// Unfollow ends follower's following of followed.
func (s *Store) Unfollow(ctx context.Context, follower, followed uuid.UUID) error {
	_, err := s.DB.Exec(ctx, `DELETE FROM follows WHERE follower_id = $1 AND followed_id = $2`, follower, followed)
	return err
}

// Block blocks a user; follows and friendship between the two end.
func (s *Store) Block(ctx context.Context, blocker, blocked uuid.UUID) error {
	if blocker == blocked {
		return ErrForbidden
	}
	return s.pairTx(ctx, blocker, blocked, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `INSERT INTO blocks (blocker_id, blocked_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`, blocker, blocked); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `DELETE FROM follows WHERE (follower_id = $1 AND followed_id = $2)
			OR (follower_id = $2 AND followed_id = $1)`, blocker, blocked); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `DELETE FROM friendships WHERE (requester_id = $1 AND addressee_id = $2)
			OR (requester_id = $2 AND addressee_id = $1)`, blocker, blocked)
		return err
	})
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

// FeedItem is something in the user's news: a route or journey someone
// published, or (with activity) a friend's hike or a comment on one's own
// item.
type FeedItem struct {
	Kind          string    `json:"kind" enum:"route,journey,hike,comment"`
	Target        string    `json:"target" enum:"route,journey" doc:"What the item is about"`
	ID            string    `json:"id" doc:"The route's or journey's id; empty for a hike on one the user may not see"`
	Title         string    `json:"title" doc:"Empty with the id"`
	OwnerUsername string    `json:"owner_username" doc:"Who did it: published, hiked or commented"`
	OwnerName     string    `json:"owner_name"`
	PublishedAt   time.Time `json:"published_at" doc:"When it happened"`
	DistanceM     float64   `json:"distance_m"`
	AscentM       float64   `json:"ascent_m"`
	DurationS     int       `json:"duration_s"`
	SACGrade      int       `json:"sac_grade"`
	SACMax        int       `json:"sac_max"`
	Stages        int       `json:"stages" doc:"Journeys only"`
	DoneOn        *string   `json:"done_on,omitempty" format:"date" doc:"Hikes: the day"`
	Excerpt       string    `json:"excerpt,omitempty" doc:"Comments: the beginning"`
}

// A journey's totals over its stage routes, for j.
const journeySums = `CROSS JOIN LATERAL (
	SELECT count(st.id)::int AS stages, coalesce(sum(sr.distance_m), 0)::float8 AS distance_m,
		coalesce(sum(sr.ascent_m), 0)::float8 AS ascent_m, coalesce(sum(sr.duration_s), 0)::int AS duration_s,
		coalesce(max(sr.sac_grade), 0)::int AS sac_grade, coalesce(max(sr.sac_max), 0)::int AS sac_max
	FROM stages st LEFT JOIN routes sr ON sr.id = st.route_id WHERE st.journey_id = j.id
) js`

// What $1 may see without a link: their own, public ones and those shared
// with them (a stage route through its journey).
const (
	seesRoute = `(r.owner_id = $1 OR CASE WHEN r.journey_id IS NULL THEN r.visibility = 'public' ELSE
		EXISTS (SELECT FROM journeys rj WHERE rj.id = r.journey_id AND (rj.owner_id = $1 OR rj.visibility = 'public'))
		OR EXISTS (SELECT FROM grants g WHERE g.journey_id = r.journey_id AND g.user_id = $1) END
		OR EXISTS (SELECT FROM grants g WHERE g.route_id = r.id AND g.user_id = $1))`
	seesJourney = `(j.owner_id = $1 OR j.visibility = 'public'
		OR EXISTS (SELECT FROM grants g WHERE g.journey_id = j.id AND g.user_id = $1))`
)

// Feed returns the user's news from before before, newest first: what the
// people they follow published; with activity also what their friends
// published and hiked (unless they switched that off) and comments on the
// user's routes and journeys. Nothing from banned users or across a block.
func (s *Store) Feed(ctx context.Context, user uuid.UUID, before time.Time, limit int, activity bool) ([]FeedItem, error) {
	rows, err := s.DB.Query(ctx, `WITH friends AS (
		SELECT CASE WHEN f.requester_id = $1 THEN f.addressee_id ELSE f.requester_id END AS id
		FROM friendships f WHERE f.accepted_at IS NOT NULL AND $4 AND (f.requester_id = $1 OR f.addressee_id = $1)
	), people AS (
		SELECT followed_id AS id FROM follows WHERE follower_id = $1 UNION SELECT id FROM friends
	), apart AS (
		SELECT blocked_id AS id FROM blocks WHERE blocker_id = $1 UNION SELECT blocker_id FROM blocks WHERE blocked_id = $1
	), actors AS (
		SELECT u.id, u.username, u.display_name, u.share_hikes AND u.id IN (SELECT id FROM friends) AS hikes
		FROM users u WHERE u.banned_at IS NULL AND u.id NOT IN (SELECT id FROM apart)
	)
	SELECT * FROM (
		SELECT 'route' AS kind, 'route' AS target, r.id, r.title, a.username, a.display_name, r.published_at AS at,
			r.distance_m::float8, r.ascent_m::float8, r.duration_s, r.sac_grade::int, r.sac_max::int, 0, NULL::date, ''
		FROM people p JOIN actors a ON a.id = p.id
		JOIN routes r ON r.owner_id = p.id AND r.visibility = 'public' AND r.journey_id IS NULL
		WHERE r.published_at < $2
		UNION ALL
		SELECT 'journey', 'journey', j.id, j.title, a.username, a.display_name, j.published_at,
			js.distance_m, js.ascent_m, js.duration_s, js.sac_grade, js.sac_max, js.stages, NULL, ''
		FROM people p JOIN actors a ON a.id = p.id
		JOIN journeys j ON j.owner_id = p.id AND j.visibility = 'public' `+journeySums+`
		WHERE j.published_at < $2
		UNION ALL
		-- Hikes: marked as hiked, or recorded in the app.
		SELECT 'hike', 'route', CASE WHEN `+seesRoute+` THEN r.id END, CASE WHEN `+seesRoute+` THEN r.title ELSE '' END,
			a.username, a.display_name, d.created_at,
			r.distance_m::float8, r.ascent_m::float8, r.duration_s, r.sac_grade::int, r.sac_max::int, 0, d.done_on, ''
		FROM actors a JOIN done_marks d ON d.user_id = a.id JOIN routes r ON r.id = d.route_id
		WHERE a.hikes AND d.created_at < $2
		UNION ALL
		SELECT 'hike', 'journey', CASE WHEN `+seesJourney+` THEN j.id END, CASE WHEN `+seesJourney+` THEN j.title ELSE '' END,
			a.username, a.display_name, d.created_at,
			js.distance_m, js.ascent_m, js.duration_s, js.sac_grade, js.sac_max, js.stages, d.done_on, ''
		FROM actors a JOIN done_marks d ON d.user_id = a.id JOIN journeys j ON j.id = d.journey_id `+journeySums+`
		WHERE a.hikes AND d.created_at < $2
		UNION ALL
		SELECT 'hike', 'route', CASE WHEN `+seesRoute+` THEN r.id END, CASE WHEN `+seesRoute+` THEN r.title ELSE '' END,
			a.username, a.display_name, r.hiked_at,
			r.distance_m::float8, r.ascent_m::float8, r.duration_s, r.sac_grade::int, r.sac_max::int, 0,
			(r.hiked_at AT TIME ZONE 'Europe/Zurich')::date, ''
		FROM actors a JOIN routes r ON r.owner_id = a.id AND r.source = 'recorded'
		WHERE a.hikes AND r.hiked_at < $2
		UNION ALL
		-- On the user's own routes and journeys.
		SELECT 'comment', CASE WHEN c.route_id IS NULL THEN 'journey' ELSE 'route' END, coalesce(c.route_id, c.journey_id),
			coalesce(r.title, j.title), a.username, a.display_name, c.created_at, 0, 0, 0, 0, 0, 0, NULL, left(c.body, 160)
		FROM comments c JOIN actors a ON a.id = c.author_id
		LEFT JOIN routes r ON r.id = c.route_id LEFT JOIN journeys j ON j.id = c.journey_id
		WHERE $4 AND c.author_id <> $1 AND coalesce(r.owner_id, j.owner_id) = $1 AND c.created_at < $2
	) feed WHERE $4 OR kind IN ('route', 'journey') ORDER BY at DESC, id LIMIT $3`, user, before, limit, activity)
	if err != nil {
		return nil, fmt.Errorf("community: feed: %w", err)
	}
	defer rows.Close()
	out := []FeedItem{}
	for rows.Next() {
		var it FeedItem
		var id *uuid.UUID
		var doneOn *time.Time
		if err := rows.Scan(&it.Kind, &it.Target, &id, &it.Title, &it.OwnerUsername, &it.OwnerName, &it.PublishedAt,
			&it.DistanceM, &it.AscentM, &it.DurationS, &it.SACGrade, &it.SACMax, &it.Stages, &doneOn, &it.Excerpt); err != nil {
			return nil, err
		}
		if id != nil {
			it.ID = id.String()
		}
		if doneOn != nil {
			d := doneOn.Format(time.DateOnly)
			it.DoneOn = &d
		}
		out = append(out, it)
	}
	return out, rows.Err()
}
