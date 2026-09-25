package community

import (
	"context"
	"errors"
	"strings"
	"testing"

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
	if _, err := pool.Exec(ctx, `INSERT INTO blocks (blocker_id, blocked_id) VALUES ($1, $2)`, owner.ID, fan.ID); err != nil {
		t.Fatal(err)
	}
	if err := s.AddComment(ctx, target, fan, "Hallo", nil); !errors.Is(err, ErrBlocked) {
		t.Errorf("blocked: %v", err)
	}
	if err := s.SetCommentsEnabled(ctx, target, false); err != nil {
		t.Fatal(err)
	}
	if err := s.AddComment(ctx, target, owner, "Hallo", nil); !errors.Is(err, ErrCommentsOff) {
		t.Errorf("off: %v", err)
	}
}
