package reminders

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/mailer"
	"github.com/tellbow/alvyo/api/internal/testdb"
)

func TestReminders(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	user := func(name, locale string) uuid.UUID {
		var id uuid.UUID
		if err := pool.QueryRow(ctx, `INSERT INTO users (email, username, display_name, locale, email_verified_at)
			VALUES ($1 || '@example.ch', $1, initcap($1), $2, now()) RETURNING id`, name, locale).Scan(&id); err != nil {
			t.Fatal(err)
		}
		return id
	}
	owner, anna, nosy := user("wodan", "de"), user("anna", "fr"), user("nosy", "de")
	var journey uuid.UUID
	if err := pool.QueryRow(ctx, `INSERT INTO journeys (owner_id, title) VALUES ($1, 'Via Alpina') RETURNING id`,
		owner).Scan(&journey); err != nil {
		t.Fatal(err)
	}
	// Three stages from 1 July 2027; the first night is booked, the second not.
	for i, booked := range []bool{true, false, false} {
		if _, err := pool.Exec(ctx, `INSERT INTO stages (journey_id, position, title, planned_date, accommodation_booked)
			VALUES ($1, $2, $3, $4, $5)`, journey, i, []string{"Gaflei – Sargans", "", "Elm"}[i],
			time.Date(2027, 7, 1+i, 0, 0, 0, 0, time.UTC), booked); err != nil {
			t.Fatal(err)
		}
	}
	// Anna comes along; nosy only sees the journey.
	if _, err := pool.Exec(ctx, `INSERT INTO grants (journey_id, user_id, role, along) VALUES ($1, $2, 'viewer', true), ($1, $3, 'viewer', false)`,
		journey, anna, nosy); err != nil {
		t.Fatal(err)
	}
	rec := &mailer.Recorder{}
	now := time.Date(2027, 6, 10, 7, 0, 0, 0, zurich) // 21 days before, before eight
	s := &Store{DB: pool, Mail: rec, PublicURL: "https://alvyo.test", Now: func() time.Time { return now }}

	check := func() []mailer.Message {
		t.Helper()
		before := len(rec.Sent())
		if err := s.Check(ctx); err != nil {
			t.Fatal(err)
		}
		return rec.Sent()[before:]
	}
	if got := check(); len(got) != 0 {
		t.Errorf("before eight: %+v", got)
	}
	now = now.Add(2 * time.Hour)
	got := check()
	if len(got) != 2 {
		t.Fatalf("three weeks before: %+v", got)
	}
	for _, m := range got {
		switch m.To {
		case "wodan@example.ch":
			if m.Subject != "«Via Alpina» in drei Wochen: Übernachtungen buchen" || !strings.Contains(m.Text, "- Etappe 2\n") ||
				strings.Contains(m.Text, "Gaflei") || strings.Contains(m.Text, "Elm") || !strings.Contains(m.Text, "https://alvyo.test/journeys/"+journey.String()) {
				t.Errorf("owner: %+v", m)
			}
		case "anna@example.ch":
			if !strings.Contains(m.Subject, "réserver les nuits") || !strings.Contains(m.Text, "Étape 2") {
				t.Errorf("anna: %+v", m)
			}
		default:
			t.Errorf("to %s", m.To)
		}
	}
	if got := check(); len(got) != 0 {
		t.Errorf("sent twice: %+v", got)
	}

	// Anna turns them off; two days before, the owner gets the weather.
	if err := s.Set(ctx, journey, anna, false); err != nil {
		t.Fatal(err)
	}
	if on, _ := s.On(ctx, journey, anna); on {
		t.Error("anna still on")
	}
	now = time.Date(2027, 6, 29, 9, 0, 0, 0, zurich)
	if got := check(); len(got) != 1 || got[0].To != "wodan@example.ch" || got[0].Subject != "«Via Alpina» übermorgen: das Wetter" {
		t.Errorf("weather: %+v", got)
	}
	now = now.AddDate(0, 0, 1)
	if got := check(); len(got) != 1 || got[0].Subject != "«Via Alpina» beginnt morgen" {
		t.Errorf("start: %+v", got)
	}

	// All booked: no reminder to book for another start.
	if _, err := pool.Exec(ctx, `UPDATE stages SET accommodation_booked = true, planned_date = planned_date + 30 WHERE journey_id = $1`,
		journey); err != nil {
		t.Fatal(err)
	}
	now = time.Date(2027, 7, 10, 9, 0, 0, 0, zurich)
	if got := check(); len(got) != 0 {
		t.Errorf("all booked: %+v", got)
	}
}
