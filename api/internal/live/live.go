// Package live shares a hike's position with the hiker's contacts while it
// lasts, and alerts them when it does not end in time.
package live

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"slices"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tellbow/alvyo/api/internal/mailer"
	"github.com/tellbow/alvyo/api/internal/routes"
)

// Limits and times.
const (
	MaxContacts = 10
	// Every is how often positions are kept.
	Every = 5 * time.Minute
	// Grace after the expected end before the contacts are alerted.
	Grace = 30 * time.Minute
	// LinkFor is how long the link works after the end.
	LinkFor = 24 * time.Hour
	// KeepFor is how long a share and its positions are kept after the end.
	KeepFor = 7 * 24 * time.Hour
	// maxDuration bounds the expected end.
	maxDuration = 72 * time.Hour
)

// Errors.
var (
	ErrNotFound     = errors.New("live: not found")
	ErrDuplicate    = errors.New("live: contact exists")
	ErrTooMany      = errors.New("live: too many contacts")
	ErrNoRecipients = errors.New("live: choose at least one contact")
	ErrEnded        = errors.New("live: the hike ended")
	ErrBadEnd       = errors.New("live: the expected end must be in the next 72 hours")
)

// Contact is someone to share with.
type Contact struct {
	ID    string `json:"id" format:"uuid"`
	Name  string `json:"name"`
	Email string `json:"email" format:"email"`
}

// Store keeps contacts and shares and sends the e-mails.
type Store struct {
	DB        *pgxpool.Pool
	Mail      mailer.Sender
	PublicURL string
	Now       func() time.Time // for tests; time.Now otherwise
}

func (s *Store) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

// Contacts lists a user's contacts by name.
func (s *Store) Contacts(ctx context.Context, owner uuid.UUID) ([]Contact, error) {
	rows, err := s.DB.Query(ctx, `SELECT id, name, email FROM contacts WHERE owner_id = $1 ORDER BY lower(name), email`, owner)
	if err != nil {
		return nil, fmt.Errorf("live: contacts: %w", err)
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (Contact, error) {
		var c Contact
		var id uuid.UUID
		err := r.Scan(&id, &c.Name, &c.Email)
		c.ID = id.String()
		return c, err
	})
}

// AddContact adds a contact, at most MaxContacts. The user's row is locked,
// so two at once cannot both be the tenth.
func (s *Store) AddContact(ctx context.Context, owner uuid.UUID, name, email string) (Contact, error) {
	var c Contact
	var id uuid.UUID
	err := pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `SELECT 1 FROM users WHERE id = $1 FOR UPDATE`, owner); err != nil {
			return err
		}
		return tx.QueryRow(ctx, `INSERT INTO contacts (owner_id, name, email)
			SELECT $1, $2, $3 WHERE (SELECT count(*) FROM contacts WHERE owner_id = $1) < $4
			RETURNING id, name, email`, owner, name, email, MaxContacts).Scan(&id, &c.Name, &c.Email)
	})
	var pg *pgconn.PgError
	switch {
	case errors.As(err, &pg) && pg.Code == "23505":
		return c, ErrDuplicate
	case errors.Is(err, pgx.ErrNoRows):
		return c, ErrTooMany
	case err != nil:
		return c, fmt.Errorf("live: add contact: %w", err)
	}
	c.ID = id.String()
	return c, nil
}

// DeleteContact removes a contact; running shares keep their recipients.
func (s *Store) DeleteContact(ctx context.Context, owner, id uuid.UUID) error {
	res, err := s.DB.Exec(ctx, `DELETE FROM contacts WHERE id = $1 AND owner_id = $2`, id, owner)
	if err != nil {
		return err
	}
	if res.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// Hiker is who shares, as the e-mails name them.
type Hiker struct {
	ID          uuid.UUID
	DisplayName string
	Email       string
	Locale      string
}

// Start is a hike to share.
type Start struct {
	RouteID     *uuid.UUID
	Title       string
	ContactIDs  []uuid.UUID
	ExpectedEnd time.Time
}

// Share is a started share, for the hiker.
type Share struct {
	ID          string    `json:"id" format:"uuid"`
	Token       string    `json:"token" doc:"The link is /live/{token}"`
	ExpectedEnd time.Time `json:"expected_end"`
	Recipients  []string  `json:"recipients" doc:"Names of those who got the link"`
}

// Start shares a hike with some of the hiker's contacts and e-mails them
// the link. A share still running ends: one at a time.
func (s *Store) Start(ctx context.Context, h Hiker, st Start) (Share, error) {
	now := s.now()
	if !st.ExpectedEnd.After(now) || st.ExpectedEnd.After(now.Add(maxDuration)) {
		return Share{}, ErrBadEnd
	}
	var sh Share
	var recipients []Contact
	err := pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `SELECT id, name, email FROM contacts WHERE owner_id = $1 AND id = ANY($2)`, h.ID, st.ContactIDs)
		if err != nil {
			return err
		}
		recipients, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (Contact, error) {
			var c Contact
			var id uuid.UUID
			err := r.Scan(&id, &c.Name, &c.Email)
			c.ID = id.String()
			return c, err
		})
		if err != nil {
			return err
		}
		if len(recipients) == 0 {
			return ErrNoRecipients
		}
		if _, err := tx.Exec(ctx, `UPDATE live_shares SET ended_at = $2 WHERE owner_id = $1 AND ended_at IS NULL`, h.ID, now); err != nil {
			return err
		}
		var id uuid.UUID
		sh.Token = routes.NewShareToken()
		if err := tx.QueryRow(ctx, `INSERT INTO live_shares (owner_id, route_id, title, token, started_at, expected_end)
			VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`, h.ID, st.RouteID, st.Title, sh.Token, now, st.ExpectedEnd).Scan(&id); err != nil {
			return err
		}
		sh.ID = id.String()
		for _, c := range recipients {
			if _, err := tx.Exec(ctx, `INSERT INTO live_recipients (share_id, name, email) VALUES ($1, $2, $3)
				ON CONFLICT DO NOTHING`, id, c.Name, c.Email); err != nil {
				return err
			}
			sh.Recipients = append(sh.Recipients, c.Name)
		}
		return nil
	})
	if err != nil {
		return Share{}, err
	}
	sh.ExpectedEnd = st.ExpectedEnd
	link := s.link(sh.Token)
	for _, c := range recipients {
		s.send(ctx, startMail(h, c.Name, st.Title, st.ExpectedEnd, link, c.Email))
	}
	return sh, nil
}

func (s *Store) link(token string) string { return s.PublicURL + "/live/" + token }

func (s *Store) send(ctx context.Context, m mailer.Message) {
	if err := s.Mail.Send(ctx, m); err != nil {
		slog.ErrorContext(ctx, "live e-mail", "err", err)
	}
}

// Fix is a position the app recorded.
type Fix struct {
	Lon float64   `json:"lon" minimum:"5.5" maximum:"11"`
	Lat float64   `json:"lat" minimum:"45.5" maximum:"48.2"`
	At  time.Time `json:"t"`
}

// AddPositions records positions of a running share: the latest always, and
// one per Every for the way so far.
func (s *Store) AddPositions(ctx context.Context, owner, id uuid.UUID, pts []Fix) error {
	slices.SortFunc(pts, func(a, b Fix) int { return a.At.Compare(b.At) })
	return pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		var ended *time.Time
		err := tx.QueryRow(ctx, `SELECT ended_at FROM live_shares WHERE id = $1 AND owner_id = $2 FOR UPDATE`,
			id, owner).Scan(&ended)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if ended != nil {
			return ErrEnded
		}
		// Read after the lock, not with it: a statement sees only what was
		// committed when it began, and an upload at the same time may just
		// have kept a point.
		var lastKept *time.Time
		if err := tx.QueryRow(ctx, `SELECT max(at) FROM live_positions WHERE share_id = $1`, id).Scan(&lastKept); err != nil {
			return err
		}
		now := s.now()
		var latest *Fix
		for i, p := range pts {
			if p.At.After(now.Add(time.Minute)) {
				continue // a clock ahead: not trusted
			}
			if lastKept == nil || p.At.Sub(*lastKept) >= Every {
				if _, err := tx.Exec(ctx, `INSERT INTO live_positions (share_id, at, lon, lat) VALUES ($1, $2, $3, $4)
					ON CONFLICT DO NOTHING`, id, p.At, p.Lon, p.Lat); err != nil {
					return err
				}
				at := p.At
				lastKept = &at
			}
			latest = &pts[i]
		}
		if latest == nil {
			return nil
		}
		// Only the latest counts: one update, not one per point.
		_, err = tx.Exec(ctx, `UPDATE live_shares SET last_lon = $2, last_lat = $3, last_at = $4
			WHERE id = $1 AND (last_at IS NULL OR last_at < $4)`, id, latest.Lon, latest.Lat, latest.At)
		return err
	})
}

// Extend moves the expected end («später»); after an alert the contacts
// hear that the hiker is back in touch.
func (s *Store) Extend(ctx context.Context, h Hiker, id uuid.UUID, end time.Time) error {
	now := s.now()
	if !end.After(now) || end.After(now.Add(maxDuration)) {
		return ErrBadEnd
	}
	return s.change(ctx, h, id, `expected_end = $3, alerted_at = NULL`, end, func(title string, wasAlerted bool, rs []Contact) {
		if wasAlerted {
			for _, c := range rs {
				s.send(ctx, allClearMail(h, c.Name, title, &end, c.Email))
			}
		}
	})
}

// End ends the sharing; after an alert the contacts hear that all is well.
func (s *Store) End(ctx context.Context, h Hiker, id uuid.UUID) error {
	return s.change(ctx, h, id, `ended_at = $3`, s.now(), func(title string, wasAlerted bool, rs []Contact) {
		if wasAlerted {
			for _, c := range rs {
				s.send(ctx, allClearMail(h, c.Name, title, nil, c.Email))
			}
		}
	})
}

func (s *Store) change(ctx context.Context, h Hiker, id uuid.UUID, set string, v time.Time, after func(string, bool, []Contact)) error {
	var title string
	var alerted *time.Time
	err := s.DB.QueryRow(ctx, `WITH old AS (SELECT alerted_at FROM live_shares WHERE id = $1 AND owner_id = $2 AND ended_at IS NULL)
		UPDATE live_shares SET `+set+` WHERE id = $1 AND owner_id = $2 AND ended_at IS NULL
		RETURNING title, (SELECT alerted_at FROM old)`, id, h.ID, v).Scan(&title, &alerted)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	rs, err := s.recipients(ctx, id)
	if err != nil {
		return err
	}
	after(title, alerted != nil, rs)
	return nil
}

func (s *Store) recipients(ctx context.Context, id uuid.UUID) ([]Contact, error) {
	rows, err := s.DB.Query(ctx, `SELECT name, email FROM live_recipients WHERE share_id = $1 ORDER BY name`, id)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (Contact, error) {
		var c Contact
		err := r.Scan(&c.Name, &c.Email)
		return c, err
	})
}
