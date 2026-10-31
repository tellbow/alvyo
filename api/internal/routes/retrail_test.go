package routes

import (
	"context"
	"testing"

	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/routing"
	"github.com/tellbow/alvyo/api/internal/testdb"
)

// A route planned while the trail network was missing: once it is there,
// its legs and grade say so, the version stays.
func TestRetrail(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	var owner uuid.UUID
	if err := pool.QueryRow(ctx, `INSERT INTO users (email, username, display_name) VALUES ('o@example.ch', 'owner', 'Owner') RETURNING id`).Scan(&owner); err != nil {
		t.Fatal(err)
	}
	s := &Store{DB: pool}
	m := &routing.TrailMatcher{DB: pool}

	// A footpath off the network, so T2 by guess.
	l := leg(8.0, 40)
	run := func(v string) []routing.Run { return []routing.Run{{From: 0, To: 40, Value: v}} }
	l.Details.Trail, l.SAC = run("none"), routing.SACSummary{Max: 3, UnofficialM: 1500}
	r, err := s.Create(ctx, owner, Meta{Title: "Uferweg", Visibility: "private"}, content(l))
	if err != nil {
		t.Fatal(err)
	}
	if n, err := s.Retrail(ctx, m); err != nil || n != 0 {
		t.Fatalf("without the network: %d changed, %v", n, err)
	}

	if _, err := pool.Exec(ctx, `INSERT INTO tlm_hiking_paths (id, category, geom)
		VALUES (1, 'Wanderweg', ST_Multi(ST_Transform(ST_SetSRID(ST_MakeLine(ST_MakePoint(7.99, 46.5), ST_MakePoint(8.03, 46.5)), 4326), 2056)))`); err != nil {
		t.Fatal(err)
	}
	if n, err := s.Retrail(ctx, m); err != nil || n != 1 {
		t.Fatalf("with the network: %d changed, %v", n, err)
	}
	got, err := s.Get(ctx, uuid.MustParse(r.ID))
	if err != nil {
		t.Fatal(err)
	}
	if got.Version != r.Version || got.Legs[0].Trails["Wanderweg"] < 1400 || got.Legs[0].Trails["none"] != 0 {
		t.Errorf("version %d (was %d), trails %v", got.Version, r.Version, got.Legs[0].Trails)
	}
	// A Wanderweg without an OSM grade is T1–T2, no longer a guess.
	if got.Totals.SACGrade != 1 || got.Totals.SACMax != 2 || got.Legs[0].SAC.UnofficialM != 0 {
		t.Errorf("SAC T%d–T%d, guessed %.0f m", got.Totals.SACGrade, got.Totals.SACMax, got.Legs[0].SAC.UnofficialM)
	}
	if n, err := s.Retrail(ctx, m); err != nil || n != 0 {
		t.Errorf("again: %d changed, %v", n, err)
	}

	// Deleted while the run goes on: skipped, not an error (feedback issue 37).
	if ok, err := s.RetrailOne(ctx, m, uuid.New()); ok || err != nil {
		t.Errorf("a deleted route: %v, %v", ok, err)
	}
}
