package official

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tellbow/alvyo/api/internal/imports"
	"github.com/tellbow/alvyo/api/internal/journeys"
	"github.com/tellbow/alvyo/api/internal/routes"
	"github.com/tellbow/alvyo/api/internal/routing"
	"github.com/tellbow/alvyo/api/internal/testdb"
	"github.com/tellbow/alvyo/swiss/geo"
)

type flatSampler struct{}

func (flatSampler) Sample(_ context.Context, pts []geo.Point) ([]float64, error) {
	return make([]float64, len(pts)), nil
}

func newSyncer(t *testing.T) (*Syncer, *pgxpool.Pool) {
	t.Helper()
	pool := testdb.New(t)
	rs := &routes.Store{DB: pool}
	im := &imports.Importer{
		Router: &routing.Router{Elevation: flatSampler{}, Trails: &routing.TrailMatcher{DB: pool}},
		Routes: rs, Journeys: &journeys.Store{DB: pool, Routes: rs},
	}
	old := minRoutes
	minRoutes = 1
	t.Cleanup(func() { minRoutes = old })
	return &Syncer{DB: pool, Importer: im}, pool
}

// stage is a Wanderland stage as the import loads it: pieces (WKT).
type stage struct {
	from, to, wkt string
}

// load replaces the imported data, as import-wanderland.sh does.
func load(t *testing.T, pool *pgxpool.Pool, rs map[string][]stage) {
	t.Helper()
	ctx := context.Background()
	exec := func(sql string, args ...any) {
		t.Helper()
		if _, err := pool.Exec(ctx, sql, args...); err != nil {
			t.Fatal(err)
		}
	}
	exec(`DELETE FROM wanderland_stages`)
	exec(`DELETE FROM wanderland_routes`)
	exec(`DELETE FROM wanderland_transport`)
	// The boat across the lake of the stage Luzern – Altdorf.
	exec(`INSERT INTO wanderland_transport (mode, geom) VALUES ('boat', 'MULTILINESTRING((8.31 47.05, 8.60 46.90))')`)
	for nr, stages := range rs {
		kind := "local"
		if len(stages) > 1 {
			kind = "national"
		}
		exec(`INSERT INTO wanderland_routes (nr, name, kind) VALUES ($1, $2, $3)`, nr, "Route "+nr, kind)
		for i, st := range stages {
			exec(`INSERT INTO wanderland_stages (nr, stage, start_name, end_name, geom)
				VALUES ($1, $2, $3, $4, ST_Multi(ST_GeomFromText($5, 4326)))`, nr, i+1, st.from, st.to, st.wkt)
		}
	}
	exec(`INSERT INTO wanderland_import (imported_at) VALUES (clock_timestamp())
		ON CONFLICT (one) DO UPDATE SET imported_at = excluded.imported_at`)
}

type row struct {
	routeID, journeyID *uuid.UUID
}

func official(t *testing.T, pool *pgxpool.Pool, nr string) (r row, ok bool) {
	t.Helper()
	err := pool.QueryRow(context.Background(), `SELECT route_id, journey_id FROM official WHERE nr = $1`, nr).
		Scan(&r.routeID, &r.journeyID)
	return r, err == nil
}

var (
	// Two stages from west to east, the second one stored east to west and
	// in two pieces with a loop round the station between them.
	sargansWeisstannen = []stage{
		{"Sargans", "Mels", "MULTILINESTRING((9.44 47.05, 9.42 47.04))"},
		{"Mels", "Weisstannen", "MULTILINESTRING((9.35 47.00, 9.38 47.02), (9.38 47.02, 9.42 47.04), (9.38 47.02, 9.381 47.021, 9.382 47.02, 9.38 47.02))"},
	}
	versoix = []stage{{"Sauverny", "Versoix", "MULTILINESTRING((6.12 46.31, 6.16 46.30))"}}
)

func TestSyncCreatesRoutesAndJourneys(t *testing.T) {
	s, pool := newSyncer(t)
	ctx := context.Background()
	load(t, pool, map[string][]stage{"1": sargansWeisstannen, "104": versoix})

	res, ran, err := s.Sync(ctx)
	if err != nil || !ran {
		t.Fatalf("sync: ran %v, err %v", ran, err)
	}
	if res.Created != 2 || res.Failed != 0 {
		t.Fatalf("result %+v, want 2 created", res)
	}
	r, ok := official(t, pool, "104")
	if !ok || r.routeID == nil {
		t.Fatalf("route 104: %+v %v", r, ok)
	}
	route, err := s.Importer.Routes.Get(ctx, *r.routeID)
	if err != nil {
		t.Fatal(err)
	}
	if route.Title != "Route 104" || route.Visibility != "public" || route.OwnerUsername != Username {
		t.Errorf("route 104: %q %s by %s", route.Title, route.Visibility, route.OwnerUsername)
	}

	j1, ok := official(t, pool, "1")
	if !ok || j1.journeyID == nil {
		t.Fatalf("route 1: %+v %v", j1, ok)
	}
	j, err := s.Importer.Journeys.Get(ctx, *j1.journeyID)
	if err != nil {
		t.Fatal(err)
	}
	if j.Visibility != "public" || len(j.StageList) != 2 || j.StageList[1].Title != "Mels – Weisstannen" {
		t.Fatalf("journey: %s, stages %+v", j.Visibility, j.StageList)
	}
	// Stage 1 ends where stage 2 starts; the loop is left out (6.95 km, with
	// the loop 7.3 km).
	s1, s2 := j.StageList[0].Route, j.StageList[1].Route
	if d := geo.Distance(geo.Point{Lon: s1.End[0], Lat: s1.End[1]}, geo.Point{Lon: s2.Start[0], Lat: s2.Start[1]}); d > 10 {
		t.Errorf("stage 1 ends %.0f m from where stage 2 starts", d)
	}
	if d := s2.Totals.DistanceM; d < 6900 || d > 7000 {
		t.Errorf("stage 2: %.0f m", d)
	}

	// Nothing new imported: nothing to do.
	if _, ran, err := s.Sync(ctx); ran || err != nil {
		t.Fatalf("second sync: ran %v, err %v", ran, err)
	}
}

func TestSyncUpdatesInPlaceAndDeletes(t *testing.T) {
	s, pool := newSyncer(t)
	ctx := context.Background()
	load(t, pool, map[string][]stage{"1": sargansWeisstannen, "104": versoix, "105": versoix})
	if _, _, err := s.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	before, _ := official(t, pool, "1")

	// A third stage; 104 gone; 105 the same.
	longer := append(append([]stage{}, sargansWeisstannen...), stage{"Weisstannen", "Foopass", "MULTILINESTRING((9.35 47.00, 9.30 46.98))"})
	load(t, pool, map[string][]stage{"1": longer, "105": versoix})
	res, ran, err := s.Sync(ctx)
	if err != nil || !ran {
		t.Fatalf("sync: ran %v, err %v", ran, err)
	}
	if res.Updated != 1 || res.Deleted != 1 || res.Unchanged != 1 {
		t.Fatalf("result %+v, want 1 updated, 1 deleted, 1 unchanged", res)
	}
	after, _ := official(t, pool, "1")
	if *after.journeyID != *before.journeyID {
		t.Fatal("the journey was replaced instead of updated")
	}
	j, err := s.Importer.Journeys.Get(ctx, *after.journeyID)
	if err != nil {
		t.Fatal(err)
	}
	if len(j.StageList) != 3 || j.StageList[2].Title != "Weisstannen – Foopass" || j.StageList[2].Route == nil {
		t.Fatalf("stages %+v", j.StageList)
	}
	if _, ok := official(t, pool, "104"); ok {
		t.Error("route 104 is still there")
	}
}

func TestSyncRefusesAnImportWithTooFewRoutes(t *testing.T) {
	s, pool := newSyncer(t)
	ctx := context.Background()
	load(t, pool, map[string][]stage{"1": sargansWeisstannen, "104": versoix})
	if _, _, err := s.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	minRoutes = 2
	load(t, pool, map[string][]stage{"104": versoix})
	if _, _, err := s.Sync(ctx); err == nil {
		t.Fatal("synced an import with one route")
	}
	if _, ok := official(t, pool, "1"); !ok {
		t.Fatal("route 1 was deleted")
	}
}

func TestSyncCutsStagesWhereTheyRide(t *testing.T) {
	s, pool := newSyncer(t)
	ctx := context.Background()
	load(t, pool, map[string][]stage{"7": {{"Luzern", "Altdorf",
		"MULTILINESTRING((8.30 47.05, 8.31 47.05), (8.31 47.05, 8.60 46.90), (8.62 46.88, 8.60 46.90))"}}})
	if res, _, err := s.Sync(ctx); err != nil || res.Created != 1 {
		t.Fatalf("sync: %+v, %v", res, err)
	}
	r, _ := official(t, pool, "7")
	if r.journeyID == nil {
		t.Fatal("a stage with a boat in it is not a journey of two stages")
	}
	j, err := s.Importer.Journeys.Get(ctx, *r.journeyID)
	if err != nil {
		t.Fatal(err)
	}
	if len(j.StageList) != 2 {
		t.Fatalf("stages %+v", j.StageList)
	}
	first, second := j.StageList[0], j.StageList[1]
	if first.Title != "Luzern – Altdorf (1/2)" || second.Title != "Luzern – Altdorf (2/2)" ||
		first.TransferBefore != nil || second.TransferBefore == nil || *second.TransferBefore != "pt" {
		t.Errorf("stages %q, %q, transfer %v", first.Title, second.Title, second.TransferBefore)
	}
	// Walked: some 760 m and 2.7 km, not the 27 km across the lake.
	for _, st := range j.StageList {
		if d := st.Route.Totals.DistanceM; d > 3000 {
			t.Errorf("%s: %.0f m walked", st.Title, d)
		}
	}
}
