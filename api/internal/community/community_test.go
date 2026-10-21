package community

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/dbq"
	"github.com/tellbow/alvyo/api/internal/testdb"
)

func TestAddCommentErrors(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	var owner, fan dbq.User
	for _, u := range []*dbq.User{&owner, &fan} {
		name := "owner"
		if u == &fan {
			name = "fan"
		}
		if err := pool.QueryRow(ctx, `INSERT INTO users (email, username, display_name) VALUES ($1, $2, $3) RETURNING id`,
			name+"@example.ch", name, name).Scan(&u.ID); err != nil {
			t.Fatal(err)
		}
	}
	var journey uuid.UUID
	if err := pool.QueryRow(ctx, `INSERT INTO journeys (owner_id, title, visibility) VALUES ($1, 'Via Alpina', 'public') RETURNING id`,
		owner.ID).Scan(&journey); err != nil {
		t.Fatal(err)
	}
	s := &Store{DB: pool}
	target := Target{Kind: Journey, ID: journey, OwnerID: owner.ID, Title: "Via Alpina"}

	if err := s.AddComment(ctx, target, owner, "Schön", nil); err != nil {
		t.Fatal(err)
	}
	// A comment the database refuses is an error, not "blocked".
	if err := s.AddComment(ctx, target, fan, strings.Repeat("x", 2001), nil); err == nil || errors.Is(err, ErrBlocked) || errors.Is(err, ErrCommentsOff) {
		t.Errorf("too long: %v", err)
	}

	// A reply to a comment deleted while it is written: the comment is gone
	// (feedback issue 27).
	var first uuid.UUID
	if err := pool.QueryRow(ctx, `SELECT id FROM comments WHERE author_id = $1`, owner.ID).Scan(&first); err != nil {
		t.Fatal(err)
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if _, err := tx.Exec(ctx, `DELETE FROM comments WHERE id = $1`, first); err != nil {
		t.Fatal(err)
	}
	done := make(chan error)
	go func() { done <- s.AddComment(ctx, target, fan, "Antwort", &first) }()
	for waiting := false; !waiting; time.Sleep(20 * time.Millisecond) {
		if err := pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE wait_event_type = 'Lock')`).
			Scan(&waiting); err != nil {
			t.Fatal(err)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err := <-done; !errors.Is(err, ErrNotFound) {
		t.Errorf("reply to a deleted comment: %v", err)
	}

	if err := s.AddComment(ctx, target, fan, "Hallo", nil); err != nil {
		t.Fatal(err)
	}
	var fans uuid.UUID
	if err := pool.QueryRow(ctx, `SELECT id FROM comments WHERE author_id = $1`, fan.ID).Scan(&fans); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `INSERT INTO blocks (blocker_id, blocked_id) VALUES ($1, $2)`, owner.ID, fan.ID); err != nil {
		t.Fatal(err)
	}
	if err := s.AddComment(ctx, target, fan, "Hallo", nil); !errors.Is(err, ErrBlocked) {
		t.Errorf("blocked: %v", err)
	}
	// Nor can an earlier comment change once blocked (feedback issue 28).
	if err := s.EditComment(ctx, target, fans, fan.ID, "anders"); !errors.Is(err, ErrBlocked) {
		t.Errorf("blocked edit: %v", err)
	}
	if err := s.SetCommentsEnabled(ctx, target, false); err != nil {
		t.Fatal(err)
	}
	if err := s.AddComment(ctx, target, owner, "Hallo", nil); !errors.Is(err, ErrCommentsOff) {
		t.Errorf("off: %v", err)
	}

	// The item deleted since the handler loaded it (feedback issue 30).
	if _, err := pool.Exec(ctx, `DELETE FROM journeys WHERE id = $1`, journey); err != nil {
		t.Fatal(err)
	}
	if err := s.AddComment(ctx, target, owner, "Hallo", nil); !errors.Is(err, ErrNotFound) {
		t.Errorf("deleted item: %v", err)
	}
	if _, err := s.Social(ctx, target, Viewer{ID: fan.ID}); !errors.Is(err, ErrNotFound) {
		t.Errorf("social of a deleted item: %v", err)
	}
}
