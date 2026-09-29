// Package reminders e-mails the owner of a journey and the people who come
// along before it starts: three weeks before to book the accommodation (if
// some is not booked), two days before to check the weather, the day before
// that it starts. The app reminds on the phone as well.
package reminders

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tellbow/alvyo/api/internal/mailer"
)

// Kinds of reminders, and how many days before the start each is sent.
var Kinds = []struct {
	Kind   string
	Before int
}{{"book", 21}, {"weather", 2}, {"start", 1}}

// SendFrom is the hour (Swiss time) from which a day's reminders go out.
const SendFrom = 8

var zurich = func() *time.Location {
	loc, err := time.LoadLocation("Europe/Zurich")
	if err != nil {
		return time.UTC
	}
	return loc
}()

// Store finds due reminders, sends them and keeps who turned them off.
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

// CheckEvery sends the due reminders every interval until ctx ends.
func (s *Store) CheckEvery(ctx context.Context, interval time.Duration) {
	for {
		if err := s.Check(ctx); err != nil && ctx.Err() == nil {
			slog.WarnContext(ctx, "reminders", "err", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(interval):
		}
	}
}

// due is one reminder to send.
type due struct {
	journeyID uuid.UUID
	userID    uuid.UUID
	kind      string
	startOn   time.Time
	title     string
	email     string
	name      string
	locale    string
	unbooked  []string // stages whose accommodation is not booked, for «book»
}

// Check sends the reminders due today, each once per journey, person and
// start date; «book» only while some accommodation is not booked.
func (s *Store) Check(ctx context.Context) error {
	now := s.now().In(zurich)
	if now.Hour() < SendFrom {
		return nil
	}
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
	for _, k := range Kinds {
		start := today.AddDate(0, 0, k.Before)
		// The journeys starting then (their first planned stage), their owner
		// and the people along with an account, who did not turn reminders off.
		rows, err := s.DB.Query(ctx, `
			WITH starts AS (
				SELECT journey_id, min(planned_date) AS start_on
				FROM stages WHERE status = 'planned' AND planned_date IS NOT NULL
				GROUP BY journey_id
			), people AS (
				SELECT j.id AS journey_id, j.owner_id AS user_id FROM journeys j
				UNION
				SELECT g.journey_id, coalesce(g.user_id, v.id)
				FROM grants g LEFT JOIN users v ON v.email = g.email AND v.email_verified_at IS NOT NULL
				WHERE g.journey_id IS NOT NULL AND g.along AND coalesce(g.user_id, v.id) IS NOT NULL
			)
			SELECT j.id, u.id, j.title, u.email, u.display_name, u.locale,
				-- Nights not booked yet: planned stages but the last, by position and title.
				coalesce((SELECT array_agg(st.position ORDER BY st.position)
					FROM stages st WHERE st.journey_id = j.id AND st.status = 'planned'
						AND NOT st.accommodation_booked
						AND st.position < (SELECT max(position) FROM stages WHERE journey_id = j.id)), '{}'),
				coalesce((SELECT array_agg(st.title ORDER BY st.position)
					FROM stages st WHERE st.journey_id = j.id AND st.status = 'planned'
						AND NOT st.accommodation_booked
						AND st.position < (SELECT max(position) FROM stages WHERE journey_id = j.id)), '{}')
			FROM starts s
			JOIN journeys j ON j.id = s.journey_id
			JOIN people p ON p.journey_id = j.id
			JOIN users u ON u.id = p.user_id AND u.email_verified_at IS NOT NULL AND u.banned_at IS NULL
			WHERE s.start_on = $1
				AND NOT EXISTS (SELECT 1 FROM journey_reminders_off o WHERE o.journey_id = j.id AND o.user_id = u.id)
				AND NOT EXISTS (SELECT 1 FROM journey_reminders r
					WHERE r.journey_id = j.id AND r.user_id = u.id AND r.kind = $2 AND r.start_on = $1)`,
			start, k.Kind)
		if err != nil {
			return fmt.Errorf("reminders: %w", err)
		}
		var list []due
		for rows.Next() {
			d := due{kind: k.Kind, startOn: start}
			var positions []int32
			var titles []string
			if err := rows.Scan(&d.journeyID, &d.userID, &d.title, &d.email, &d.name, &d.locale, &positions, &titles); err != nil {
				rows.Close()
				return err
			}
			for i, p := range positions {
				d.unbooked = append(d.unbooked, stageName(d.locale, int(p)+1, titles[i]))
			}
			list = append(list, d)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}
		for _, d := range list {
			if d.kind == "book" && len(d.unbooked) == 0 {
				continue // all booked: nothing to remind of
			}
			// Kept first: a failed e-mail is not sent again and again.
			tag, err := s.DB.Exec(ctx, `INSERT INTO journey_reminders (journey_id, user_id, kind, start_on)
				VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING`, d.journeyID, d.userID, d.kind, d.startOn)
			if err != nil {
				return err
			}
			if tag.RowsAffected() == 0 {
				continue
			}
			if err := s.Mail.Send(ctx, reminderMail(d, s.PublicURL+"/journeys/"+d.journeyID.String())); err != nil {
				slog.ErrorContext(ctx, "reminder e-mail", "err", err)
			}
		}
	}
	return nil
}

// On says whether the user gets reminders for the journey.
func (s *Store) On(ctx context.Context, journeyID, userID uuid.UUID) (bool, error) {
	var off bool
	err := s.DB.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM journey_reminders_off WHERE journey_id = $1 AND user_id = $2)`,
		journeyID, userID).Scan(&off)
	return !off, err
}

// Set turns the user's reminders for the journey on or off.
func (s *Store) Set(ctx context.Context, journeyID, userID uuid.UUID, on bool) error {
	var err error
	if on {
		_, err = s.DB.Exec(ctx, `DELETE FROM journey_reminders_off WHERE journey_id = $1 AND user_id = $2`, journeyID, userID)
	} else {
		_, err = s.DB.Exec(ctx, `INSERT INTO journey_reminders_off (journey_id, user_id) VALUES ($1, $2)
			ON CONFLICT DO NOTHING`, journeyID, userID)
	}
	return err
}
