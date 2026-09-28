package routes

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/testdb"
)

func TestRevisions(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	var owner, editor uuid.UUID
	for _, u := range []struct {
		name string
		id   *uuid.UUID
	}{{"owner", &owner}, {"edi", &editor}} {
		if err := pool.QueryRow(ctx, `INSERT INTO users (email, username, display_name) VALUES ($1 || '@example.ch', $1, $1) RETURNING id`,
			u.name).Scan(u.id); err != nil {
			t.Fatal(err)
		}
	}
	s := &Store{DB: pool}
	r, err := s.Create(ctx, owner, Meta{Title: "Grat", Visibility: "private"}, content(leg(8.0, 4)))
	if err != nil {
		t.Fatal(err)
	}
	id := uuid.MustParse(r.ID)

	// A title alone is no new line.
	if r, err = s.Update(ctx, id, 1, Meta{Title: "Gratweg", Visibility: "private"}, nil, owner); err != nil {
		t.Fatal(err)
	}
	longer := content(leg(8.0, 4), leg(8.002, 4))
	if r, err = s.Update(ctx, id, r.Version, r.Meta, &longer, editor); err != nil {
		t.Fatal(err)
	}
	revs, err := s.Revisions(ctx, id)
	if err != nil || len(revs) != 1 {
		t.Fatalf("revisions: %+v %v", revs, err)
	}
	if rv := revs[0]; rv.Version != 2 || rv.SavedBy != "owner" || rv.DistanceM < 150 || rv.DistanceM > 160 {
		t.Errorf("the line before: %+v", rv)
	}
	rv, c, err := s.RevisionContent(ctx, id, 2)
	if err != nil || len(c.Legs) != 1 || len(c.Anchors) != 2 || c.Profile != "hike" || rv.Version != 2 {
		t.Fatalf("content: %d legs %v", len(c.Legs), err)
	}
	if _, _, err := s.RevisionContent(ctx, id, 3); !errors.Is(err, ErrNotFound) {
		t.Errorf("the current version is no revision: %v", err)
	}

	// The editor's line is kept with their name; the last 20 are kept.
	for range MaxRevisions + 2 {
		if r, err = s.Update(ctx, id, r.Version, r.Meta, &longer, owner); err != nil {
			t.Fatal(err)
		}
		if revs, _ = s.Revisions(ctx, id); revs[len(revs)-1].Version == 3 && revs[len(revs)-1].SavedBy != "edi" {
			t.Fatalf("the editor's line: %+v", revs[len(revs)-1])
		}
	}
	revs, _ = s.Revisions(ctx, id)
	if len(revs) != MaxRevisions || revs[0].Version != r.Version-1 || revs[len(revs)-1].Version != r.Version-MaxRevisions {
		t.Fatalf("%d revisions, %d to %d (route at %d)", len(revs), revs[0].Version, revs[len(revs)-1].Version, r.Version)
	}
}
