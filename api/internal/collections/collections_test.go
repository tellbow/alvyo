package collections

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/testdb"
)

// An item added while the collection is deleted: the collection is gone,
// not a server error (feedback issue 30). The handler has loaded it already.
func TestAddItemToDeletedCollection(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	var owner uuid.UUID
	if err := pool.QueryRow(ctx, `INSERT INTO users (email, username, display_name) VALUES ('c@example.ch', 'hiker', 'H') RETURNING id`).Scan(&owner); err != nil {
		t.Fatal(err)
	}
	s := &Store{DB: pool}
	id, err := s.Create(ctx, owner, Meta{Title: "Wishlist", Visibility: "private"})
	if err != nil {
		t.Fatal(err)
	}
	if err := s.Delete(ctx, id); err != nil {
		t.Fatal(err)
	}
	if err := s.AddItem(ctx, id, "route", uuid.New(), "", owner); !errors.Is(err, ErrNotFound) {
		t.Errorf("add item: %v", err)
	}
}
