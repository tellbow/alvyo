package journeys

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/routes"
	"github.com/tellbow/alvyo/api/internal/routing"
	"github.com/tellbow/alvyo/api/internal/testdb"
)

// content builds a single-leg route going east from lon0 at 46.5° N
// (0.0005° ≈ 38 m per segment, 5 m climb per segment).
func content(lon0 float64, n int) routes.Content {
	coords := make([][3]float64, n+1)
	for i := range coords {
		coords[i] = [3]float64{lon0 + float64(i)*0.0005, 46.5, 1000 + float64(i)*5}
	}
	run := func(v string) []routing.Run { return []routing.Run{{From: 0, To: n, Value: v}} }
	return routes.Content{
		Profile: "hike",
		Anchors: []routes.Anchor{{Lon: lon0, Lat: 46.5}, {Lon: coords[n][0], Lat: 46.5}},
		Legs: []routing.Leg{{Coordinates: coords, SAC: routing.SACSummary{Max: 3},
			Details: routing.Details{SAC: run("T2"), Surface: run("gravel"), WayType: run("path"), Trail: run("Wanderweg")}}},
	}
}

func TestJourneyLifecycle(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	var owner uuid.UUID
	if err := pool.QueryRow(ctx, `INSERT INTO users (email, username, display_name) VALUES ('j@example.ch', 'hiker', 'H') RETURNING id`).Scan(&owner); err != nil {
		t.Fatal(err)
	}
	rs := &routes.Store{DB: pool}
	s := &Store{DB: pool, Routes: rs}

	j, err := s.Create(ctx, owner, Meta{Title: "Via Alpina", Visibility: "private"})
	if err != nil {
		t.Fatal(err)
	}
	jid := uuid.MustParse(j.ID)
	for range 3 {
		if err := s.AddStage(ctx, jid, owner, NewStage{}); err != nil {
			t.Fatal(err)
		}
	}
	j, _ = s.Get(ctx, jid)
	if len(j.StageList) != 3 || j.StageList[2].Position != 2 {
		t.Fatalf("stages %+v", j.StageList)
	}
	st := func(i int) uuid.UUID { return uuid.MustParse(j.StageList[i].ID) }

	// Stage 1 and 2 connect (stage 2 starts where stage 1 ends: 8.0 + 10×0.0005).
	if _, err := s.SetStageRoute(ctx, jid, st(0), owner, "Day 1", content(8.0, 10)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.SetStageRoute(ctx, jid, st(0), owner, "again", content(8.0, 10)); !errors.Is(err, ErrHasRoute) {
		t.Errorf("second route: %v", err)
	}
	if _, err := s.SetStageRoute(ctx, jid, st(1), owner, "Day 2", content(8.005, 10)); err != nil {
		t.Fatal(err)
	}
	// Stage 3 copies a library route ~2 km further east.
	lib, err := rs.Create(ctx, owner, routes.Meta{Title: "Library", Visibility: "private"}, content(8.04, 10))
	if err != nil {
		t.Fatal(err)
	}
	libID := uuid.MustParse(lib.ID)
	if err := s.DeleteStage(ctx, jid, st(2)); err != nil {
		t.Fatal(err)
	}
	if err := s.AddStage(ctx, jid, owner, NewStage{Title: "Day 3", CopyFrom: &libID}); err != nil {
		t.Fatal(err)
	}

	j, _ = s.Get(ctx, jid)
	if len(j.StageList) != 3 || j.StageList[2].Route == nil || j.StageList[2].Title != "Day 3" {
		t.Fatalf("after copy: %+v", j.StageList)
	}
	if g := j.StageList[1].Gap; g == nil || g.Status != "ok" {
		t.Errorf("stage 2 gap %+v, want ok", g)
	}
	if g := j.StageList[2].Gap; g == nil || g.Status != "gap" || g.Metres < 1500 {
		t.Errorf("stage 3 gap %+v, want a gap of ~2 km", g)
	}
	if len(j.Profile.Breaks) != 3 || j.Profile.Breaks[0] != 0 || len(j.Profile.Distance) > profilePoints+60 {
		t.Errorf("profile breaks %v, %d points", j.Profile.Breaks, len(j.Profile.Distance))
	}
	if j.Totals.AscentM != 150 {
		t.Errorf("total ascent %.0f", j.Totals.AscentM)
	}

	// A transfer acknowledges the gap; progress counts done and ignores skipped.
	pt, done, skipped := "pt", "done", "skipped"
	if err := s.UpdateStage(ctx, jid, st(2), 1, StagePatch{TransferBefore: &pt}); err != nil {
		t.Fatal(err)
	}
	if err := s.UpdateStage(ctx, jid, st(0), 1, StagePatch{Status: &done}); err != nil {
		t.Fatal(err)
	}
	if err := s.UpdateStage(ctx, jid, st(1), 1, StagePatch{Status: &skipped}); err != nil {
		t.Fatal(err)
	}
	j, _ = s.Get(ctx, jid)
	if j.StageList[2].Gap.Status != "transfer" {
		t.Errorf("gap with transfer: %s", j.StageList[2].Gap.Status)
	}
	if p := j.Progress; p.StagesDone != 1 || p.StagesTotal != 2 || p.DistanceDoneM == 0 || p.DistanceDoneM >= p.DistanceTotalM {
		t.Errorf("progress %+v", p)
	}

	// Reorder and delete keep positions dense.
	if err := s.Reorder(ctx, jid, []uuid.UUID{st(2), st(0), st(1)}); err != nil {
		t.Fatal(err)
	}
	if err := s.Reorder(ctx, jid, []uuid.UUID{st(0), st(1)}); !errors.Is(err, ErrBadOrder) {
		t.Errorf("partial order: %v", err)
	}
	j, _ = s.Get(ctx, jid)
	if j.StageList[0].Title != "Day 3" {
		t.Errorf("order after reorder: %s", j.StageList[0].Title)
	}

	// Stage routes stay out of the route library, which still has the original.
	lst, _ := rs.ListByOwner(ctx, owner, 10)
	if len(lst) != 1 || lst[0].ID != lib.ID {
		t.Errorf("library %+v", lst)
	}
	sums, _ := s.ListByOwner(ctx, owner)
	if len(sums) != 1 || sums[0].Stages != 3 || sums[0].StagesDone != 1 {
		t.Errorf("journey list %+v", sums)
	}

	if err := s.Delete(ctx, jid); err != nil {
		t.Fatal(err)
	}
	var left int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM routes WHERE journey_id IS NOT NULL`).Scan(&left); err != nil {
		t.Fatal(err)
	}
	if left != 0 {
		t.Errorf("%d stage routes left after deleting the journey", left)
	}
}

func TestCopyRouteOfSomeoneElse(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	var a, b uuid.UUID
	for _, u := range []struct {
		name string
		id   *uuid.UUID
	}{{"aaa", &a}, {"bbb", &b}} {
		if err := pool.QueryRow(ctx, `INSERT INTO users (email, username, display_name) VALUES ($1 || '@x.ch', $1, $1) RETURNING id`, u.name).Scan(u.id); err != nil {
			t.Fatal(err)
		}
	}
	rs := &routes.Store{DB: pool}
	s := &Store{DB: pool, Routes: rs}
	other, _ := rs.Create(ctx, b, routes.Meta{Title: "B's", Visibility: "public"}, content(8.0, 4))
	j, _ := s.Create(ctx, a, Meta{Title: "A's journey", Visibility: "private"})
	oid := uuid.MustParse(other.ID)
	if err := s.AddStage(ctx, uuid.MustParse(j.ID), a, NewStage{CopyFrom: &oid}); !errors.Is(err, ErrNotYours) {
		t.Errorf("copy of foreign route: %v", err)
	}
}

func TestStagePlaces(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	var owner uuid.UUID
	if err := pool.QueryRow(ctx, `INSERT INTO users (email, username, display_name) VALUES ('p@example.ch', 'placer', 'P') RETURNING id`).Scan(&owner); err != nil {
		t.Fatal(err)
	}
	place := func(kind, name string, lon, lat float64) string {
		var id uuid.UUID
		if err := pool.QueryRow(ctx, `INSERT INTO places (kind, name, source, source_id, geom)
			VALUES ($1, $2, 'osm', $2, ST_SetSRID(ST_MakePoint($3, $4), 4326)) RETURNING id`, kind, name, lon, lat).Scan(&id); err != nil {
			t.Fatal(err)
		}
		return id.String()
	}
	// The route runs from 8.0 to 8.005 at 46.5° N.
	place("pt_stop", "Start stop", 8.0001, 46.5)      // ~8 m from the start
	hut := place("hut", "End hut", 8.005, 46.501)     // ~111 m from the end
	hotel := place("hotel", "End hotel", 8.005, 46.5) // at the end, but hotels are not suggested
	far := place("pt_stop", "Far stop", 8.025, 46.5)  // 1.5 km beyond the end

	s := &Store{DB: pool, Routes: &routes.Store{DB: pool}}
	j, _ := s.Create(ctx, owner, Meta{Title: "Places", Visibility: "private"})
	jid := uuid.MustParse(j.ID)
	for range 2 {
		if err := s.AddStage(ctx, jid, owner, NewStage{}); err != nil {
			t.Fatal(err)
		}
	}
	j, _ = s.Get(ctx, jid)
	st0, st1 := uuid.MustParse(j.StageList[0].ID), uuid.MustParse(j.StageList[1].ID)
	if _, err := s.SetStageRoute(ctx, jid, st0, owner, "Day 1", content(8.0, 10)); err != nil {
		t.Fatal(err)
	}
	get := func() Journey {
		t.Helper()
		j, err := s.Get(ctx, jid)
		if err != nil {
			t.Fatal(err)
		}
		return j
	}
	// version is the stage's current version, to change it.
	version := func(id uuid.UUID) int {
		for _, st := range get().StageList {
			if st.ID == id.String() {
				return st.Version
			}
		}
		t.Fatalf("no stage %s", id)
		return 0
	}

	j = get()
	sp, ep := j.StageList[0].StartPlace, j.StageList[0].EndPlace
	if sp == nil || sp.Name != "Start stop" || !sp.Suggested || sp.DistanceM > 10 {
		t.Errorf("suggested start %+v", sp)
	}
	if ep == nil || ep.Name != "End hut" || !ep.Suggested || ep.DistanceM < 100 || ep.DistanceM > 120 {
		t.Errorf("suggested end %+v", ep)
	}
	if j.StageList[1].StartPlace != nil {
		t.Errorf("stage without route got a suggestion: %+v", j.StageList[1].StartPlace)
	}

	// An explicit choice wins, even far away; clearing it brings back the suggestion.
	empty, acc, booked := "", "Gasthaus", true
	if err := s.UpdateStage(ctx, jid, st0, version(st0), StagePatch{EndPlaceID: &hotel, StartPlaceID: &far,
		Accommodation: &acc, Booked: &booked}); err != nil {
		t.Fatal(err)
	}
	j = get()
	s0 := j.StageList[0]
	if s0.EndPlace == nil || s0.EndPlace.ID != hotel || s0.EndPlace.Suggested {
		t.Errorf("chosen end %+v", s0.EndPlace)
	}
	if s0.StartPlace == nil || s0.StartPlace.ID != far || s0.StartPlace.DistanceM < 1800 {
		t.Errorf("chosen far start %+v", s0.StartPlace)
	}
	if s0.Accommodation != "Gasthaus" || !s0.AccommodationBooked {
		t.Errorf("accommodation %q booked=%v", s0.Accommodation, s0.AccommodationBooked)
	}
	if err := s.UpdateStage(ctx, jid, st0, version(st0), StagePatch{EndPlaceID: &empty}); err != nil {
		t.Fatal(err)
	}
	if ep := get().StageList[0].EndPlace; ep == nil || ep.ID != hut || !ep.Suggested {
		t.Errorf("end after clearing %+v", ep)
	}

	// A place on a stage without a route has no distance.
	if err := s.UpdateStage(ctx, jid, st1, version(st1), StagePatch{StartPlaceID: &hut}); err != nil {
		t.Fatal(err)
	}
	if sp := get().StageList[1].StartPlace; sp == nil || sp.ID != hut || sp.DistanceM != 0 {
		t.Errorf("place without route %+v", sp)
	}
	// A change based on an older version is refused.
	if err := s.UpdateStage(ctx, jid, st1, version(st1)-1, StagePatch{StartPlaceID: &empty}); !errors.Is(err, ErrStageVersion) {
		t.Errorf("stale version: %v", err)
	}
	unknown := uuid.NewString()
	if err := s.UpdateStage(ctx, jid, st1, version(st1), StagePatch{StartPlaceID: &unknown}); !errors.Is(err, routes.ErrInvalid) {
		t.Errorf("unknown place: %v", err)
	}

	// Beyond 400 m nothing is suggested.
	if _, err := pool.Exec(ctx, `DELETE FROM places WHERE name IN ('Start stop', 'End hut')`); err != nil {
		t.Fatal(err)
	}
	if err := s.UpdateStage(ctx, jid, st0, version(st0), StagePatch{StartPlaceID: &empty}); err != nil {
		t.Fatal(err)
	}
	if sp := get().StageList[0].StartPlace; sp != nil {
		t.Errorf("start without a place nearby: %+v", sp)
	}
}

func TestAddStagesAtOnce(t *testing.T) {
	// Stages added at the same moment (two editors, a double click) all get
	// a place of their own.
	ctx := context.Background()
	pool := testdb.New(t)
	var owner uuid.UUID
	if err := pool.QueryRow(ctx, `INSERT INTO users (email, username, display_name) VALUES ('j@example.ch', 'hiker', 'H') RETURNING id`).Scan(&owner); err != nil {
		t.Fatal(err)
	}
	s := &Store{DB: pool, Routes: &routes.Store{DB: pool}}
	j, err := s.Create(ctx, owner, Meta{Title: "Via Alpina", Visibility: "private"})
	if err != nil {
		t.Fatal(err)
	}
	jid := uuid.MustParse(j.ID)
	errs := make(chan error, 12)
	for i := range 12 {
		go func() {
			first := 0
			n := NewStage{}
			if i%2 == 0 {
				n.Position = &first // inserted at the front, shifting the others
			}
			errs <- s.AddStage(ctx, jid, owner, n)
		}()
	}
	for range 12 {
		if err := <-errs; err != nil {
			t.Error(err)
		}
	}
	j, _ = s.Get(ctx, jid)
	for i, st := range j.StageList {
		if st.Position != i {
			t.Fatalf("positions: %d at %d", st.Position, i)
		}
	}
	if len(j.StageList) != 12 {
		t.Errorf("%d stages", len(j.StageList))
	}
}

func TestTinyLoopStage(t *testing.T) {
	// A stage route that is a loop of a few metres simplifies to nothing;
	// the journey still opens.
	ctx := context.Background()
	pool := testdb.New(t)
	var owner uuid.UUID
	if err := pool.QueryRow(ctx, `INSERT INTO users (email, username, display_name) VALUES ('j@example.ch', 'hiker', 'H') RETURNING id`).Scan(&owner); err != nil {
		t.Fatal(err)
	}
	s := &Store{DB: pool, Routes: &routes.Store{DB: pool}}
	j, err := s.Create(ctx, owner, Meta{Title: "Klein", Visibility: "private"})
	if err != nil {
		t.Fatal(err)
	}
	jid := uuid.MustParse(j.ID)
	if err := s.AddStage(ctx, jid, owner, NewStage{}); err != nil {
		t.Fatal(err)
	}
	j, _ = s.Get(ctx, jid)
	loop := [][3]float64{{8, 46.5, 1000}, {8.00002, 46.5, 1000}, {8.00002, 46.50002, 1000}, {8, 46.5, 1000}}
	run := func(v string) []routing.Run { return []routing.Run{{From: 0, To: 3, Value: v}} }
	c := routes.Content{
		Profile: "hike",
		Anchors: []routes.Anchor{{Lon: 8, Lat: 46.5}, {Lon: 8, Lat: 46.5}},
		Legs: []routing.Leg{{Coordinates: loop, SAC: routing.SACSummary{Max: 1},
			Details: routing.Details{SAC: run("T1"), Surface: run("paved"), WayType: run("road"), Trail: run("none")}}},
	}
	if _, err := s.SetStageRoute(ctx, jid, uuid.MustParse(j.StageList[0].ID), owner, "Runde", c); err != nil {
		t.Fatal(err)
	}
	j, err = s.Get(ctx, jid)
	if err != nil {
		t.Fatalf("journey with a tiny loop: %v", err)
	}
	if r := j.StageList[0].Route; r == nil || len(r.Line) < 2 {
		t.Errorf("stage route %+v", r)
	}
}
