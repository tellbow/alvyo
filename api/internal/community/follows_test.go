package community

import (
	"context"
	"sync"
	"testing"

	"github.com/tellbow/alvyo/api/internal/dbq"
	"github.com/tellbow/alvyo/api/internal/testdb"
)

func twoUsers(t *testing.T, s *Store) (a, b dbq.User) {
	t.Helper()
	for _, u := range []*dbq.User{&a, &b} {
		name := "anna"
		if u == &b {
			name = "bea"
		}
		if err := s.DB.QueryRow(context.Background(), `INSERT INTO users (email, username, display_name) VALUES ($1, $2, $3)
			RETURNING id`, name+"@example.ch", name, name).Scan(&u.ID); err != nil {
			t.Fatal(err)
		}
	}
	return a, b
}

// A follow or friend request made at the same moment as a block does not
// survive it (feedback issue 31).
func TestBlockRacesFollow(t *testing.T) {
	ctx := context.Background()
	s := &Store{DB: testdb.New(t)}
	a, b := twoUsers(t, s)
	for range 20 {
		var wg sync.WaitGroup
		wg.Go(func() {
			if err := s.Block(ctx, a.ID, b.ID); err != nil {
				t.Error(err)
			}
		})
		wg.Go(func() { _ = s.Follow(ctx, b, a.ID) })
		wg.Go(func() { _ = s.RequestFriend(ctx, b, a.ID) })
		wg.Wait()
		var follows, friendships int
		if err := s.DB.QueryRow(ctx, `SELECT (SELECT count(*) FROM follows), (SELECT count(*) FROM friendships)`).
			Scan(&follows, &friendships); err != nil {
			t.Fatal(err)
		}
		if follows != 0 || friendships != 0 {
			t.Fatalf("after the block: %d follows, %d friendships", follows, friendships)
		}
		if err := s.Unblock(ctx, a.ID, b.ID); err != nil {
			t.Fatal(err)
		}
	}
}

// Two users asking each other at the same moment are friends (feedback
// issue 32).
func TestMutualFriendRequests(t *testing.T) {
	ctx := context.Background()
	s := &Store{DB: testdb.New(t)}
	a, b := twoUsers(t, s)
	for range 20 {
		var wg sync.WaitGroup
		wg.Go(func() {
			if err := s.RequestFriend(ctx, a, b.ID); err != nil {
				t.Error(err)
			}
		})
		wg.Go(func() {
			if err := s.RequestFriend(ctx, b, a.ID); err != nil {
				t.Error(err)
			}
		})
		wg.Wait()
		if f, err := s.FriendState(ctx, a.ID, b.ID); err != nil || f != Friends {
			t.Fatalf("after asking each other: %s %v", f, err)
		}
		if err := s.Unfriend(ctx, a.ID, b.ID); err != nil {
			t.Fatal(err)
		}
	}
}
