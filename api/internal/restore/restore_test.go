package restore

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tellbow/alvyo/api/internal/testdb"
)

func exec(t *testing.T, db *pgxpool.Pool, sql string, args ...any) {
	t.Helper()
	if _, err := db.Exec(context.Background(), sql, args...); err != nil {
		t.Fatalf("%s: %v", sql, err)
	}
}

func count(t *testing.T, db *pgxpool.Pool, sql string, args ...any) int {
	t.Helper()
	var n int
	if err := db.QueryRow(context.Background(), sql, args...).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

// TestRestoreUser: anna deleted her journey and a route by mistake; the
// backup still has them, with a like from bob, who has since left.
func TestRestoreUser(t *testing.T) {
	ctx := context.Background()
	backup, live := testdb.New(t), testdb.New(t)
	anna, bob, cleo := uuid.New(), uuid.New(), uuid.New()
	journey, stage, route, kept := uuid.New(), uuid.New(), uuid.New(), uuid.New()
	photo, lostPhoto, coll := uuid.New(), uuid.New(), uuid.New()
	for _, db := range []*pgxpool.Pool{backup, live} {
		exec(t, db, `INSERT INTO users (id, email, username, display_name) VALUES
			($1, 'a@example.ch', 'anna', 'Anna'), ($2, 'c@example.ch', 'cleo', 'Cleo')`, anna, cleo)
	}
	exec(t, backup, `INSERT INTO users (id, email, username, display_name) VALUES ($1, 'b@example.ch', 'bob', 'Bob')`, bob)
	insertRoute := func(db *pgxpool.Pool, id uuid.UUID, title string, journeyID *uuid.UUID) {
		exec(t, db, `INSERT INTO routes (id, owner_id, title, journey_id, anchors, legs, geom, distance_m, ascent_m,
			descent_m, duration_s, duration_reverse_s, ele_min_m, ele_max_m, sac_grade, sac_max)
			VALUES ($1, $2, $3, $4, '[]', '[]',
				ST_SetSRID(ST_MakeLine(ST_MakePoint(8, 46.5, 500), ST_MakePoint(8.01, 46.5, 520)), 4326),
				760, 20, 0, 600, 580, 500, 520, 1, 2)`, id, anna, title, journeyID)
	}
	exec(t, backup, `INSERT INTO journeys (id, owner_id, title) VALUES ($1, $2, 'Via Alpina')`, journey, anna)
	insertRoute(backup, route, "Etappe 1", &journey)
	insertRoute(backup, kept, "Noch da", nil)
	insertRoute(live, kept, "Noch da, umbenannt", nil)
	exec(t, backup, `INSERT INTO stages (id, journey_id, route_id, position) VALUES ($1, $2, $3, 0)`, stage, journey, route)
	exec(t, backup, `INSERT INTO likes (user_id, journey_id) VALUES ($1, $2), ($3, $2)`, cleo, journey, bob)
	exec(t, backup, `INSERT INTO comments (author_id, journey_id, body) VALUES ($1, $2, 'Schön!')`, cleo, journey)
	exec(t, backup, `INSERT INTO photos (id, uploader_id, journey_id, width, height, bytes, position)
		VALUES ($1, $3, $4, 10, 10, 1, 0), ($2, $3, $4, 10, 10, 1, 1)`, photo, lostPhoto, anna, journey)
	// Cleo's collection is gone from the backup's view of anna: not hers.
	exec(t, backup, `INSERT INTO collections (id, owner_id, title) VALUES ($1, $2, 'Cleos')`, coll, cleo)
	exec(t, live, `INSERT INTO collections (id, owner_id, title) VALUES ($1, $2, 'Cleos')`, coll, cleo)
	exec(t, backup, `INSERT INTO collection_items (collection_id, journey_id, position) VALUES ($1, $2, 0)`, coll, journey)
	// The photo's file is still on disk, waiting in the trash.
	dir := t.TempDir()
	file := func(id uuid.UUID) string { return filepath.Join(dir, id.String()) }
	if err := os.WriteFile(file(photo), []byte("jpg"), 0o600); err != nil {
		t.Fatal(err)
	}
	exec(t, live, `INSERT INTO photo_trash (id) VALUES ($1), ($2)`, photo, lostPhoto)

	r := &Restorer{From: backup, To: live, PhotoFile: file}
	what := What{Kind: "user", ID: "anna"}
	counts, err := r.Run(ctx, what, false)
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]Count{}
	for _, c := range counts {
		got[c.Table] = c
	}
	if got["journeys"].Added != 1 || got["routes"].Added != 1 || got["likes"].Added != 1 || got["likes"].Missed != 1 ||
		got["photos"].Added != 1 || got["photos"].Missed != 1 || got["collection_items"].Added != 1 {
		t.Errorf("dry run: %+v", counts)
	}
	if n := count(t, live, `SELECT count(*) FROM journeys`); n != 0 {
		t.Fatalf("the dry run wrote %d journeys", n)
	}

	if _, err := r.Run(ctx, what, true); err != nil {
		t.Fatal(err)
	}
	if n := count(t, live, `SELECT count(*) FROM stages WHERE journey_id = $1 AND route_id = $2`, journey, route); n != 1 {
		t.Errorf("stage: %d", n)
	}
	if n := count(t, live, `SELECT count(*) FROM routes WHERE id = $1 AND ST_NPoints(geom) = 2 AND ST_Z(ST_EndPoint(geom)) = 520`, route); n != 1 {
		t.Errorf("route line not as it was: %d", n)
	}
	if n := count(t, live, `SELECT count(*) FROM routes WHERE id = $1 AND title = 'Noch da, umbenannt'`, kept); n != 1 {
		t.Errorf("an existing route was changed")
	}
	if n := count(t, live, `SELECT count(*) FROM photo_trash WHERE id = $1`, photo); n != 0 {
		t.Errorf("the restored photo is still in the trash")
	}
	if n := count(t, live, `SELECT count(*) FROM comments WHERE journey_id = $1`, journey); n != 1 {
		t.Errorf("comments: %d", n)
	}
	// Again: nothing left to add.
	counts, _ = r.Run(ctx, what, true)
	for _, c := range counts {
		if c.Added != 0 {
			t.Errorf("second run added %+v", c)
		}
	}

	if _, err := r.Run(ctx, What{Kind: "user", ID: "bob"}, false); err == nil {
		t.Error("bob is not in the live database")
	}
	if _, err := r.Run(ctx, What{Kind: "route", ID: uuid.NewString()}, false); err == nil {
		t.Error("a route the backup lacks")
	}
}

// TestDumpRestores: pg_restore runs with an empty search_path; the
// functions of generated columns must still find PostGIS.
func TestDumpRestores(t *testing.T) {
	db := testdb.New(t)
	exec(t, db, `SET search_path = ''`)
	exec(t, db, `SELECT public.shown_line(public.ST_SetSRID(public.ST_MakeLine(public.ST_MakePoint(8, 46.5), public.ST_MakePoint(8.1, 46.5)), 4326))`)
}
