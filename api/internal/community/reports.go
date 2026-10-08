package community

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/tellbow/alvyo/api/internal/admin"
)

// NewReport is what someone reports. For routes and journeys the caller
// checks that the reporter may see them.
type NewReport struct {
	Kind     string // route, journey, comment, user, photo
	TargetID uuid.UUID
	Reason   string // spam, offensive, dangerous, other
	Note     string
}

// Report files a report; a second one by the same person on the same target
// is ignored while the first is open.
func (s *Store) Report(ctx context.Context, reporter uuid.UUID, r NewReport) error {
	// What the target is now: its text for the record and whose it is.
	lookup := map[string]string{
		"route":   `SELECT title, owner_id FROM routes WHERE id = $1`,
		"journey": `SELECT title, owner_id FROM journeys WHERE id = $1`,
		"comment": `SELECT body, author_id FROM comments WHERE id = $1`,
		"user":    `SELECT username || ' (' || display_name || ')', id FROM users WHERE id = $1`,
		"photo":   `SELECT coalesce(nullif(caption, ''), '–'), uploader_id FROM photos WHERE id = $1`,
	}[r.Kind]
	if lookup == "" {
		return ErrNotFound
	}
	var excerpt string
	var subject uuid.UUID
	if err := s.DB.QueryRow(ctx, lookup, r.TargetID).Scan(&excerpt, &subject); errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	} else if err != nil {
		return err
	}
	if subject == reporter {
		return ErrForbidden
	}
	ref := func(kind string) *uuid.UUID {
		if r.Kind == kind {
			return &r.TargetID
		}
		return nil
	}
	_, err := s.DB.Exec(ctx, `INSERT INTO reports (reporter_id, kind, target_id, route_id, journey_id, comment_id,
		photo_id, user_id, excerpt, reason, note) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) ON CONFLICT DO NOTHING`,
		reporter, r.Kind, r.TargetID, ref("route"), ref("journey"), ref("comment"), ref("photo"), subject, excerpt, r.Reason, r.Note)
	return err
}

// Report is an open report as moderators see it.
type Report struct {
	ID       string    `json:"id" format:"uuid"`
	Kind     string    `json:"kind" enum:"route,journey,comment,user,photo"`
	TargetID string    `json:"target_id" format:"uuid"`
	Excerpt  string    `json:"excerpt" doc:"Title, comment text, user or photo caption as it was when reported"`
	Gone     bool      `json:"gone" doc:"The target was deleted since"`
	Subject  string    `json:"subject" doc:"Username of the owner, author or reported user"`
	Reporter string    `json:"reporter"`
	Reason   string    `json:"reason" enum:"spam,offensive,dangerous,other"`
	Note     string    `json:"note"`
	Reports  int       `json:"reports" doc:"Open reports on the same target"`
	Created  time.Time `json:"created_at"`
	// Where to look: the route or journey itself, or the one a comment is on.
	ItemKind string `json:"item_kind,omitempty" enum:"route,journey"`
	ItemID   string `json:"item_id,omitempty" format:"uuid"`
}

// OpenReports lists open reports, oldest first.
func (s *Store) OpenReports(ctx context.Context) ([]Report, error) {
	rows, err := s.DB.Query(ctx, `SELECT r.id, r.kind, r.target_id, r.excerpt,
		CASE r.kind WHEN 'route' THEN r.route_id IS NULL WHEN 'journey' THEN r.journey_id IS NULL
			WHEN 'comment' THEN r.comment_id IS NULL WHEN 'photo' THEN r.photo_id IS NULL ELSE r.user_id IS NULL END,
		coalesce(su.username, ''), coalesce(ru.username, ''), r.reason, r.note,
		count(*) OVER (PARTITION BY r.target_id), r.created_at,
		CASE WHEN coalesce(r.route_id, c.route_id, p.route_id) IS NOT NULL THEN 'route'
			WHEN coalesce(r.journey_id, c.journey_id, p.journey_id) IS NOT NULL THEN 'journey' ELSE '' END,
		coalesce(r.route_id, c.route_id, p.route_id, r.journey_id, c.journey_id, p.journey_id)
		FROM reports r
		LEFT JOIN comments c ON c.id = r.comment_id
		LEFT JOIN photos p ON p.id = r.photo_id
		LEFT JOIN users su ON su.id = r.user_id
		LEFT JOIN users ru ON ru.id = r.reporter_id
		WHERE r.resolved_at IS NULL
		ORDER BY r.created_at LIMIT 500`)
	if err != nil {
		return nil, fmt.Errorf("community: reports: %w", err)
	}
	defer rows.Close()
	out := []Report{}
	for rows.Next() {
		var rp Report
		var id, target uuid.UUID
		var item *uuid.UUID
		if err := rows.Scan(&id, &rp.Kind, &target, &rp.Excerpt, &rp.Gone, &rp.Subject, &rp.Reporter, &rp.Reason,
			&rp.Note, &rp.Reports, &rp.Created, &rp.ItemKind, &item); err != nil {
			return nil, err
		}
		rp.ID, rp.TargetID = id.String(), target.String()
		if item != nil {
			rp.ItemID = item.String()
		}
		out = append(out, rp)
	}
	return out, rows.Err()
}

// Resolve closes a report and all other open reports on the same target.
// "removed" also acts on the target: a comment or photo is deleted, a route
// or journey becomes private, a user is banned.
func (s *Store) Resolve(ctx context.Context, id, moderator uuid.UUID, resolution string) error {
	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	var kind string
	var target uuid.UUID
	err = tx.QueryRow(ctx, `SELECT kind, target_id FROM reports WHERE id = $1 AND resolved_at IS NULL FOR UPDATE`, id).
		Scan(&kind, &target)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	if resolution == "removed" {
		switch kind {
		case "comment":
			_, err = tx.Exec(ctx, `DELETE FROM comments WHERE id = $1`, target)
		case "photo": // its files go with the next trash sweep
			_, err = tx.Exec(ctx, `DELETE FROM photos WHERE id = $1`, target)
		case "route", "journey":
			_, err = tx.Exec(ctx, `UPDATE `+kind+`s SET visibility = 'private', version = version + 1, updated_at = now()
				WHERE id = $1`, target)
		case "user":
			// A moderator banning an admin (or another moderator) would
			// leave only the CLI to undo it.
			var role string
			if err = tx.QueryRow(ctx, `SELECT role FROM users WHERE id = $1`, target).Scan(&role); err == nil {
				if role != "user" {
					return ErrStaff
				}
				err = admin.BanUser(ctx, tx, target)
			}
		}
		if err != nil {
			return err
		}
	}
	if _, err := tx.Exec(ctx, `UPDATE reports SET resolved_at = now(), resolved_by = $2, resolution = $3
		WHERE target_id = $1 AND resolved_at IS NULL`, target, moderator, resolution); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
