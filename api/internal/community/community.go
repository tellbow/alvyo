// Package community holds likes, comments, follows, blocks and reports, and
// the notification e-mails they trigger.
package community

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tellbow/alvyo/api/internal/dbq"
	"github.com/tellbow/alvyo/api/internal/mailer"
	"github.com/tellbow/alvyo/swiss/geo"
)

// Errors.
var (
	ErrNotFound    = errors.New("community: not found")
	ErrForbidden   = errors.New("community: not allowed")
	ErrCommentsOff = errors.New("community: comments are switched off")
	ErrBlocked     = errors.New("community: blocked")
)

// MaxComments is how many comments an item shows (the oldest).
const MaxComments = 500

// Kind is what likes and comments are on.
type Kind string

// Kinds.
const (
	Route   Kind = "route"
	Journey Kind = "journey"
)

func (k Kind) column() string { return string(k) + "_id" }
func (k Kind) table() string  { return string(k) + "s" }

// Target is a route (not a stage route) or journey the caller may see.
type Target struct {
	Kind    Kind
	ID      uuid.UUID
	OwnerID uuid.UUID
	Title   string
	// Hidden: nothing near these places is shown to the caller (the start
	// and end of someone else's recorded hike).
	Hidden []geo.Point
}

// Store reads and writes community data and sends notifications.
type Store struct {
	DB        *pgxpool.Pool
	Mail      mailer.Sender
	PublicURL string
}

// Viewer is who looks at an item; ID is uuid.Nil when not logged in.
type Viewer struct {
	ID        uuid.UUID
	Moderator bool
}

// Comment is a comment on a route or journey.
type Comment struct {
	ID             string     `json:"id" format:"uuid"`
	ParentID       string     `json:"parent_id,omitempty" format:"uuid" doc:"The comment this replies to"`
	AuthorUsername string     `json:"author_username"`
	AuthorName     string     `json:"author_name"`
	Body           string     `json:"body"`
	CreatedAt      time.Time  `json:"created_at"`
	EditedAt       *time.Time `json:"edited_at,omitempty"`
	CanEdit        bool       `json:"can_edit" doc:"The viewer wrote it"`
	CanDelete      bool       `json:"can_delete" doc:"The viewer wrote it, owns the item or moderates"`
}

// Social is the likes and comments of an item as a viewer sees them.
type Social struct {
	Likes           int       `json:"likes"`
	Liked           bool      `json:"liked" doc:"The viewer likes it"`
	CommentsEnabled bool      `json:"comments_enabled"`
	Comments        []Comment `json:"comments" doc:"Oldest first, replies among them; without comments of people the viewer blocked and replies to those"`
	// BlockedByOwner: the owner blocked the viewer, who may not comment.
	BlockedByOwner bool `json:"-"`
}

// Social returns likes and comments of t for v.
func (s *Store) Social(ctx context.Context, t Target, v Viewer) (Social, error) {
	col := t.Kind.column()
	out := Social{Comments: []Comment{}}
	err := s.DB.QueryRow(ctx, `SELECT (SELECT count(*) FROM likes WHERE `+col+` = $1),
		EXISTS (SELECT 1 FROM likes WHERE `+col+` = $1 AND user_id = $2),
		(SELECT comments_enabled FROM `+t.Kind.table()+` WHERE id = $1),
		EXISTS (SELECT 1 FROM blocks WHERE blocker_id = $3 AND blocked_id = $2)`, t.ID, v.ID, t.OwnerID).
		Scan(&out.Likes, &out.Liked, &out.CommentsEnabled, &out.BlockedByOwner)
	if err != nil {
		return out, fmt.Errorf("community: social: %w", err)
	}
	rows, err := s.DB.Query(ctx, `WITH visible AS (
			SELECT c.* FROM comments c JOIN users u ON u.id = c.author_id
			WHERE c.`+col+` = $1 AND u.banned_at IS NULL
				AND NOT EXISTS (SELECT 1 FROM blocks b WHERE b.blocker_id = $2 AND b.blocked_id = c.author_id))
		SELECT c.id, c.parent_id, u.username, u.display_name, c.body, c.created_at, c.edited_at, c.author_id
		FROM visible c JOIN users u ON u.id = c.author_id
		WHERE c.parent_id IS NULL OR c.parent_id IN (SELECT id FROM visible)
		ORDER BY c.created_at LIMIT $3`, t.ID, v.ID, MaxComments)
	if err != nil {
		return out, fmt.Errorf("community: comments: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var c Comment
		var id, author uuid.UUID
		var parent *uuid.UUID
		if err := rows.Scan(&id, &parent, &c.AuthorUsername, &c.AuthorName, &c.Body, &c.CreatedAt, &c.EditedAt, &author); err != nil {
			return out, err
		}
		c.ID = id.String()
		if parent != nil {
			c.ParentID = parent.String()
		}
		c.CanEdit = v.ID != uuid.Nil && author == v.ID
		c.CanDelete = v.ID != uuid.Nil && (author == v.ID || t.OwnerID == v.ID || v.Moderator)
		out.Comments = append(out.Comments, c)
	}
	return out, rows.Err()
}

// Like records that user likes t (again: no change).
func (s *Store) Like(ctx context.Context, t Target, user uuid.UUID) error {
	_, err := s.DB.Exec(ctx, `INSERT INTO likes (user_id, `+t.Kind.column()+`) VALUES ($1, $2) ON CONFLICT DO NOTHING`, user, t.ID)
	return err
}

// Unlike removes user's like of t.
func (s *Store) Unlike(ctx context.Context, t Target, user uuid.UUID) error {
	_, err := s.DB.Exec(ctx, `DELETE FROM likes WHERE user_id = $1 AND `+t.Kind.column()+` = $2`, user, t.ID)
	return err
}

// SetCommentsEnabled switches comments on t on or off; existing comments
// stay but are hidden while off.
func (s *Store) SetCommentsEnabled(ctx context.Context, t Target, on bool) error {
	_, err := s.DB.Exec(ctx, `UPDATE `+t.Kind.table()+` SET comments_enabled = $2 WHERE id = $1`, t.ID, on)
	return err
}

// AddComment adds author's comment on t, or a reply to the comment parent,
// and tells the owner (and the author of the comment replied to) by e-mail.
// A reply to a reply goes to the same comment: replies are one level.
func (s *Store) AddComment(ctx context.Context, t Target, author dbq.User, body string, parent *uuid.UUID) error {
	body = strings.TrimSpace(body)
	var parentAuthor *uuid.UUID
	if parent != nil {
		var top uuid.UUID
		err := s.DB.QueryRow(ctx, `SELECT coalesce(parent_id, id), (SELECT author_id FROM comments
				WHERE id = coalesce(c.parent_id, c.id))
			FROM comments c WHERE id = $1 AND `+t.Kind.column()+` = $2`, *parent, t.ID).Scan(&top, &parentAuthor)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return fmt.Errorf("community: reply: %w", err)
		}
		parent = &top
	}
	var id uuid.UUID
	err := s.DB.QueryRow(ctx, `INSERT INTO comments (author_id, `+t.Kind.column()+`, body, parent_id)
		SELECT $1, i.id, $3, $4 FROM `+t.Kind.table()+` i
		WHERE i.id = $2 AND i.comments_enabled
			AND NOT EXISTS (SELECT 1 FROM blocks WHERE blocker_id = i.owner_id AND blocked_id = $1)
		RETURNING id`, author.ID, t.ID, body, parent).Scan(&id)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return fmt.Errorf("community: comment: %w", err)
	}
	if err != nil { // nothing inserted: find out why
		var on bool
		if qerr := s.DB.QueryRow(ctx, `SELECT comments_enabled FROM `+t.Kind.table()+` WHERE id = $1`, t.ID).Scan(&on); qerr != nil {
			return fmt.Errorf("community: comment: %w", err)
		}
		if !on {
			return ErrCommentsOff
		}
		return ErrBlocked
	}
	if t.OwnerID != author.ID {
		s.notifyComment(ctx, t, author, body)
	}
	if parentAuthor != nil && *parentAuthor != author.ID && *parentAuthor != t.OwnerID {
		s.notifyReply(ctx, t, *parentAuthor, *parent, author, body)
	}
	return nil
}

// EditComment changes the text of a comment on t; only its author may, and
// only while comments are on.
func (s *Store) EditComment(ctx context.Context, t Target, id uuid.UUID, author uuid.UUID, body string) error {
	res, err := s.DB.Exec(ctx, `UPDATE comments c SET body = $4, edited_at = now()
		FROM `+t.Kind.table()+` i
		WHERE c.id = $1 AND c.`+t.Kind.column()+` = $2 AND c.author_id = $3 AND i.id = $2 AND i.comments_enabled`,
		id, t.ID, author, strings.TrimSpace(body))
	if err != nil {
		return fmt.Errorf("community: edit comment: %w", err)
	}
	if res.RowsAffected() == 1 {
		return nil
	}
	var mine, on bool
	err = s.DB.QueryRow(ctx, `SELECT author_id = $3, (SELECT comments_enabled FROM `+t.Kind.table()+` WHERE id = $2)
		FROM comments WHERE id = $1 AND `+t.Kind.column()+` = $2`, id, t.ID, author).Scan(&mine, &on)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		return ErrNotFound
	case err != nil:
		return err
	case !mine:
		return ErrForbidden
	}
	return ErrCommentsOff
}

// DeleteComment removes a comment on t. Its author, t's owner and
// moderators may.
func (s *Store) DeleteComment(ctx context.Context, t Target, id uuid.UUID, v Viewer) error {
	res, err := s.DB.Exec(ctx, `DELETE FROM comments WHERE id = $1 AND `+t.Kind.column()+` = $2
		AND ($3 OR author_id = $4)`, id, t.ID, v.Moderator || t.OwnerID == v.ID, v.ID)
	if err != nil {
		return err
	}
	if res.RowsAffected() == 1 {
		return nil
	}
	var exists bool
	if err := s.DB.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM comments WHERE id = $1 AND `+t.Kind.column()+` = $2)`,
		id, t.ID).Scan(&exists); err != nil {
		return err
	}
	if exists {
		return ErrForbidden
	}
	return ErrNotFound
}

// SetSettings changes which notification e-mails user gets and the language
// of e-mails (nil: keep).
func (s *Store) SetSettings(ctx context.Context, user uuid.UUID, comments, follows *bool, locale *string) error {
	_, err := s.DB.Exec(ctx, `UPDATE users SET notify_comments = coalesce($2, notify_comments),
		notify_follows = coalesce($3, notify_follows), locale = coalesce($4, locale) WHERE id = $1`,
		user, comments, follows, locale)
	return err
}
