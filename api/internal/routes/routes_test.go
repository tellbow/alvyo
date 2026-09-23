package routes

import (
	"context"
	"errors"
	"math"
	"testing"

	"github.com/google/uuid"

	"github.com/tellbow/odysgeh/api/internal/routing"
	"github.com/tellbow/odysgeh/api/internal/testdb"
)

// leg builds a valid leg of n segments going east from lon0 at 46.5° N,
// climbing 5 m per segment.
func leg(lon0 float64, n int) routing.Leg {
	coords := make([][3]float64, n+1)
	for i := range coords {
		coords[i] = [3]float64{lon0 + float64(i)*0.0005, 46.5, 1000 + float64(i)*5}
	}
	run := func(v string) []routing.Run { return []routing.Run{{From: 0, To: n, Value: v}} }
	return routing.Leg{
		Coordinates: coords,
		SAC:         routing.SACSummary{Max: 3},
		Details:     routing.Details{SAC: run("T2"), Surface: run("gravel"), WayType: run("path"), Trail: run("Bergwanderweg")},
	}
}

func content(legs ...routing.Leg) Content {
	anchors := []Anchor{{Lon: legs[0].Coordinates[0][0], Lat: 46.5}}
	for _, l := range legs {
		last := l.Coordinates[len(l.Coordinates)-1]
		anchors = append(anchors, Anchor{Lon: last[0], Lat: last[1]})
	}
	return Content{Profile: "hike", Anchors: anchors, Legs: legs}
}

func TestNormalizeRecomputesNumbers(t *testing.T) {
	l := leg(8.0, 10)
	l.DistanceM, l.DurationS, l.SAC.Grade = 99999, 1, 6 // tampered by the client
	n, err := normalizeLeg(l)
	if err != nil {
		t.Fatal(err)
	}
	if math.Abs(n.DistanceM-383) > 2 { // 10 × 0.0005° lon at 46.5° ≈ 383 m
		t.Errorf("distance %.1f", n.DistanceM)
	}
	if n.SAC.Grade != 2 || n.SAC.Max != 3 || n.AscentM != 50 || n.DurationS < 300 {
		t.Errorf("normalized: grade %d max %d ascent %.0f duration %d", n.SAC.Grade, n.SAC.Max, n.AscentM, n.DurationS)
	}
	if n.Trails["Bergwanderweg"] != math.Round(n.DistanceM) {
		t.Errorf("trail breakdown %v", n.Trails)
	}
}

func TestNormalizeRejects(t *testing.T) {
	outside := leg(8.0, 3)
	outside.Coordinates[1][1] = 50 // north of Germany's border
	gappy := leg(8.0, 3)
	gappy.Details.Surface = []routing.Run{{From: 0, To: 1, Value: "gravel"}, {From: 2, To: 3, Value: "paved"}}
	badValue := leg(8.0, 3)
	badValue.Details.SAC[0].Value = "T9"
	for name, l := range map[string]routing.Leg{"outside": outside, "gappy runs": gappy, "bad value": badValue} {
		if _, err := normalizeLeg(l); !errors.Is(err, ErrInvalid) {
			t.Errorf("%s: err = %v", name, err)
		}
	}
}

func TestAssemble(t *testing.T) {
	a := leg(8.0, 4)
	b := leg(8.002, 4) // starts where a ends
	got, err := assemble(content(a, b))
	if err != nil {
		t.Fatal(err)
	}
	if got.totals.AscentM != 40 || got.totals.SACGrade != 2 {
		t.Errorf("totals %+v", got.totals)
	}
	if want := "LINESTRING Z (8.000000 46.500000 1000.0,"; got.wkt[:len(want)] != want {
		t.Errorf("wkt %s…", got.wkt[:60])
	}

	far := leg(8.01, 4) // ~700 m away from the end of a
	if _, err := assemble(content(a, far)); !errors.Is(err, ErrInvalid) {
		t.Errorf("gap between legs: %v", err)
	}
	c := content(a)
	c.Anchors = c.Anchors[:1]
	if _, err := assemble(c); !errors.Is(err, ErrInvalid) {
		t.Errorf("anchor count: %v", err)
	}
}

func TestStore(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	var owner uuid.UUID
	if err := pool.QueryRow(ctx, `INSERT INTO users (email, username, display_name) VALUES ('o@example.ch', 'owner', 'Owner') RETURNING id`).Scan(&owner); err != nil {
		t.Fatal(err)
	}
	s := &Store{DB: pool}

	r, err := s.Create(ctx, owner, Meta{Title: "Grat", Visibility: "private"}, content(leg(8.0, 4), leg(8.002, 4)))
	if err != nil {
		t.Fatal(err)
	}
	if r.Version != 1 || r.OwnerUsername != "owner" || len(r.Legs) != 2 || r.Totals.AscentM != 40 {
		t.Errorf("created %+v", r.Summary)
	}

	list, err := s.ListByOwner(ctx, owner, 10)
	if err != nil || len(list) != 1 || list[0].Title != "Grat" {
		t.Fatalf("list %v %v", list, err)
	}

	id := uuid.MustParse(r.ID)
	r2, err := s.Update(ctx, id, 1, Meta{Title: "Gratweg", Visibility: "public"}, nil)
	if err != nil || r2.Version != 2 || r2.Title != "Gratweg" || len(r2.Legs) != 2 {
		t.Fatalf("meta update: %+v %v", r2.Summary, err)
	}
	if _, err := s.Update(ctx, id, 1, Meta{Title: "stale", Visibility: "private"}, nil); !errors.Is(err, ErrVersion) {
		t.Errorf("stale update: %v", err)
	}
	longer := content(leg(8.0, 4), leg(8.002, 4), leg(8.004, 4))
	r3, err := s.Update(ctx, id, 2, r2.Meta, &longer)
	if err != nil || len(r3.Legs) != 3 || r3.Totals.AscentM != 60 {
		t.Fatalf("content update: %v %v", r3.Totals, err)
	}

	if err := s.Delete(ctx, id); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Get(ctx, id); !errors.Is(err, ErrNotFound) {
		t.Errorf("after delete: %v", err)
	}
	if _, err := s.Update(ctx, id, 3, r2.Meta, nil); !errors.Is(err, ErrNotFound) {
		t.Errorf("update deleted: %v", err)
	}
}

func TestShareToken(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	var owner uuid.UUID
	if err := pool.QueryRow(ctx, `INSERT INTO users (email, username, display_name) VALUES ('s@example.ch', 'sharer', 'S') RETURNING id`).Scan(&owner); err != nil {
		t.Fatal(err)
	}
	s := &Store{DB: pool}

	r, err := s.Create(ctx, owner, Meta{Title: "Link", Visibility: "unlisted"}, content(leg(8.0, 4)))
	if err != nil || len(r.ShareToken) != 22 {
		t.Fatalf("unlisted create: token %q err %v", r.ShareToken, err)
	}
	id := uuid.MustParse(r.ID)
	first := r.ShareToken

	// Going private and back keeps the same link.
	r, _ = s.Update(ctx, id, 1, Meta{Title: "Link", Visibility: "private"}, nil)
	r, _ = s.Update(ctx, id, 2, Meta{Title: "Link", Visibility: "unlisted"}, nil)
	if r.ShareToken != first {
		t.Errorf("token changed on visibility toggle: %q → %q", first, r.ShareToken)
	}

	rotated, err := s.RotateShareToken(ctx, id)
	if err != nil || rotated == first {
		t.Fatalf("rotate: %q %v", rotated, err)
	}
	if r, _ := s.Get(ctx, id); r.ShareToken != rotated {
		t.Errorf("stored token %q, want %q", r.ShareToken, rotated)
	}

	p, _ := s.Create(ctx, owner, Meta{Title: "Private", Visibility: "private"}, content(leg(8.0, 4)))
	if p.ShareToken != "" {
		t.Errorf("private route got a token")
	}
}
