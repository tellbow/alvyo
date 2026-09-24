package live

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/tellbow/odysgeh/api/internal/mailer"
	"github.com/tellbow/odysgeh/api/internal/testdb"
)

func TestLive(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	rec := &mailer.Recorder{}
	now := time.Date(2026, 9, 26, 8, 0, 0, 0, time.UTC)
	s := &Store{DB: pool, Mail: rec, PublicURL: "https://odysgeh.test", Now: func() time.Time { return now }}
	var uid uuid.UUID
	if err := pool.QueryRow(ctx, `INSERT INTO users (email, username, display_name, locale)
		VALUES ('anna@example.ch', 'anna', 'Anna Alpin', 'de') RETURNING id`).Scan(&uid); err != nil {
		t.Fatal(err)
	}
	h := Hiker{ID: uid, DisplayName: "Anna Alpin", Email: "anna@example.ch", Locale: "de"}

	// Contacts: unique by address, at most ten.
	bea, err := s.AddContact(ctx, uid, "Bea", "bea@example.ch")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.AddContact(ctx, uid, "Bea again", "BEA@example.ch"); !errors.Is(err, ErrDuplicate) {
		t.Errorf("same address: %v", err)
	}
	cyril, _ := s.AddContact(ctx, uid, "Cyril", "cyril@example.ch")
	for i := range 8 {
		if _, err := s.AddContact(ctx, uid, "X", fmt.Sprintf("x%d@example.ch", i)); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := s.AddContact(ctx, uid, "Eleven", "eleven@example.ch"); !errors.Is(err, ErrTooMany) {
		t.Errorf("eleventh contact: %v", err)
	}

	// Started with two contacts: they get the link.
	if _, err := s.Start(ctx, h, Start{Title: "Gratweg", ExpectedEnd: now.Add(-time.Minute), ContactIDs: []uuid.UUID{uuid.MustParse(bea.ID)}}); !errors.Is(err, ErrBadEnd) {
		t.Errorf("end in the past: %v", err)
	}
	if _, err := s.Start(ctx, h, Start{Title: "Gratweg", ExpectedEnd: now.Add(time.Hour)}); !errors.Is(err, ErrNoRecipients) {
		t.Errorf("no contacts: %v", err)
	}
	sh, err := s.Start(ctx, h, Start{Title: "Gratweg", ExpectedEnd: now.Add(6 * time.Hour),
		ContactIDs: []uuid.UUID{uuid.MustParse(bea.ID), uuid.MustParse(cyril.ID)}})
	if err != nil {
		t.Fatal(err)
	}
	mails := rec.Sent()
	if len(mails) != 2 || mails[0].Subject != "Anna Alpin teilt den Standort: «Gratweg»" ||
		!strings.Contains(mails[0].Text, "https://odysgeh.test/live/"+sh.Token) || !strings.Contains(mails[0].Text, "26.09.2026 16:00") {
		t.Fatalf("start mails: %+v", mails)
	}
	id := uuid.MustParse(sh.ID)

	// Positions: the latest always, the way one per 5 minutes.
	var pts []Fix
	for i := range 13 { // one a minute for the last 12 minutes
		pts = append(pts, Fix{Lon: 8.0 + float64(i)*0.001, Lat: 46.6, At: now.Add(time.Duration(i-12) * time.Minute)})
	}
	future := Fix{Lon: 9, Lat: 46.6, At: now.Add(time.Hour)} // a clock ahead: dropped
	pts = append(pts, future)
	if err := s.AddPositions(ctx, uid, id, pts); err != nil {
		t.Fatal(err)
	}
	v, err := s.Public(ctx, sh.Token)
	if err != nil {
		t.Fatal(err)
	}
	if len(v.Way) != 3 || v.Last == nil || v.Last.Lon != 8.012 || v.Hiker != "Anna Alpin" || v.Overdue || v.EndedAt != nil {
		t.Errorf("view: %+v", v)
	}
	if err := s.AddPositions(ctx, uuid.New(), id, pts); !errors.Is(err, ErrNotFound) {
		t.Errorf("someone else's positions: %v", err)
	}

	// Not ended 30 minutes after the expected end: one alert, to the
	// contacts and to the hiker.
	now = now.Add(6*time.Hour + 29*time.Minute)
	if err := s.Check(ctx); err != nil || len(rec.Sent()) != 2 {
		t.Fatalf("too early: %v, %d mails", err, len(rec.Sent()))
	}
	now = now.Add(time.Minute)
	if err := s.Check(ctx); err != nil {
		t.Fatal(err)
	}
	alerts := rec.Sent()[2:]
	if len(alerts) != 3 || alerts[0].Subject != "Anna Alpin hat «Gratweg» nicht beendet" ||
		!strings.Contains(alerts[0].Text, "46.60000, 8.01200 (WGS84)") || !strings.Contains(alerts[0].Text, "(LV95)") ||
		alerts[2].To != "anna@example.ch" {
		t.Fatalf("alerts: %+v", alerts)
	}
	if err := s.Check(ctx); err != nil || len(rec.Sent()) != 5 {
		t.Errorf("alerted twice: %d mails", len(rec.Sent()))
	}
	if v, _ := s.Public(ctx, sh.Token); !v.Overdue {
		t.Error("not overdue on the page")
	}

	// «Später»: the contacts hear of it; a later alert is possible again.
	if err := s.Extend(ctx, h, id, now.Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	if m := rec.Sent()[5:]; len(m) != 2 || !strings.HasPrefix(m[0].Subject, "Alles in Ordnung") || !strings.Contains(m[0].Text, "hat sich gemeldet") {
		t.Errorf("after «später»: %+v", m)
	}
	// Ended without an alert since: no more mails.
	if err := s.End(ctx, h, id); err != nil || len(rec.Sent()) != 7 {
		t.Errorf("end: %v, %d mails", err, len(rec.Sent()))
	}
	if err := s.AddPositions(ctx, uid, id, pts); !errors.Is(err, ErrEnded) {
		t.Errorf("positions after the end: %v", err)
	}

	// The link works 24 hours after the end; the rest goes after 7 days.
	now = now.Add(23 * time.Hour)
	if v, err := s.Public(ctx, sh.Token); err != nil || v.EndedAt == nil {
		t.Errorf("23 h after: %v", err)
	}
	now = now.Add(2 * time.Hour)
	if _, err := s.Public(ctx, sh.Token); !errors.Is(err, ErrNotFound) {
		t.Errorf("25 h after: %v", err)
	}
	now = now.Add(7 * 24 * time.Hour)
	if err := s.Check(ctx); err != nil {
		t.Fatal(err)
	}
	var left int
	_ = pool.QueryRow(ctx, `SELECT count(*) FROM live_positions`).Scan(&left)
	if left != 0 {
		t.Errorf("%d positions left after 7 days", left)
	}
}

func TestOneShareAtATime(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	s := &Store{DB: pool, Mail: &mailer.Recorder{}, PublicURL: "https://odysgeh.test"}
	var uid uuid.UUID
	if err := pool.QueryRow(ctx, `INSERT INTO users (email, username, display_name) VALUES ('a@example.ch', 'alone', 'A') RETURNING id`).Scan(&uid); err != nil {
		t.Fatal(err)
	}
	h := Hiker{ID: uid, DisplayName: "A", Email: "a@example.ch"}
	c, err := s.AddContact(ctx, uid, "B", "b@example.ch")
	if err != nil {
		t.Fatal(err)
	}
	start := func() Share {
		sh, err := s.Start(ctx, h, Start{Title: "T", ExpectedEnd: time.Now().Add(time.Hour), ContactIDs: []uuid.UUID{uuid.MustParse(c.ID)}})
		if err != nil {
			t.Fatal(err)
		}
		return sh
	}
	first, second := start(), start()
	if err := s.AddPositions(ctx, uid, uuid.MustParse(first.ID), []Fix{{Lon: 8, Lat: 46.6, At: time.Now()}}); !errors.Is(err, ErrEnded) {
		t.Errorf("the first share still runs: %v", err)
	}
	if err := s.AddPositions(ctx, uid, uuid.MustParse(second.ID), []Fix{{Lon: 8, Lat: 46.6, At: time.Now()}}); err != nil {
		t.Error(err)
	}
}
