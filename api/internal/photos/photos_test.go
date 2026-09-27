package photos

import (
	"context"
	"errors"
	"sync"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tellbow/alvyo/api/internal/testdb"
)

func TestAddConcurrentlyKeepsLimit(t *testing.T) {
	// Uploads at the same time are counted one after the other: a route
	// one short of its limit gets one more photo, not several.
	ctx := context.Background()
	pool := testdb.New(t)
	var user, route uuid.UUID
	if err := pool.QueryRow(ctx, `INSERT INTO users (email, username, display_name) VALUES ('p@example.ch', 'photo', 'P')
		RETURNING id`).Scan(&user); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO routes (owner_id, title, anchors, legs, geom, distance_m, ascent_m, descent_m,
			duration_s, duration_reverse_s, ele_min_m, ele_max_m, sac_grade, sac_max)
		VALUES ($1, 'R', '[]', '[]', ST_GeomFromText('LINESTRING Z (8 46.5 1000, 8.001 46.5 1000)', 4326), 1, 1, 1, 1, 1, 1, 1, 1, 1)
		RETURNING id`, user).Scan(&route); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `INSERT INTO photos (uploader_id, route_id, width, height, bytes, position)
		SELECT $1, $2, 1, 1, 1, n FROM generate_series(1, $3::int - 1) n`, user, route, MaxPerItem); err != nil {
		t.Fatal(err)
	}
	s := &Store{DB: pool, Files: &Files{Dir: t.TempDir()}}
	target := Target{Kind: "route", ID: route}
	// Connections ready and all starting together, so that they overlap;
	// no more than the pool has (4 on a CI runner), or Acquire waits forever.
	var conns []*pgxpool.Conn
	for range min(10, int(pool.Config().MaxConns)) {
		c, err := pool.Acquire(ctx)
		if err != nil {
			t.Fatal(err)
		}
		conns = append(conns, c)
	}
	for _, c := range conns {
		c.Release()
	}
	var wg sync.WaitGroup
	start := make(chan struct{})
	errs := make([]error, 10)
	for i := range errs {
		wg.Go(func() {
			<-start
			errs[i] = s.Add(ctx, target, user, Processed{Large: []byte("large"), Thumb: []byte("thumb"), Width: 1, Height: 1}, "")
		})
	}
	close(start)
	wg.Wait()
	added := 0
	for _, err := range errs {
		switch {
		case err == nil:
			added++
		case !errors.Is(err, ErrLimit):
			t.Errorf("add: %v", err)
		}
	}
	var n int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM photos WHERE route_id = $1`, route).Scan(&n); err != nil {
		t.Fatal(err)
	}
	if added != 1 || n != MaxPerItem {
		t.Errorf("%d added, %d photos; want 1 and %d", added, n, MaxPerItem)
	}
}
