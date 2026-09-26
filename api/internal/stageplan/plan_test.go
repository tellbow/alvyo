package stageplan

import (
	"context"
	"errors"
	"testing"

	"github.com/tellbow/alvyo/api/internal/routing"
	"github.com/tellbow/alvyo/api/internal/testdb"
)

func TestSplitEndsAtTheEnds(t *testing.T) {
	pool := testdb.New(t)
	ctx := context.Background()
	legs := []routing.Leg{testLeg(8.0, 1000, 51, "T2"), testLeg(8.01, 1100, 51, "T3")}
	// Stops at the first and the last vertex, and one in the middle.
	ids := map[string]string{}
	for name, lon := range map[string]float64{"start": 8.0, "middle": 8.01, "end": 8.02} {
		var id string
		if err := pool.QueryRow(ctx, `INSERT INTO places (kind, name, source, source_id, geom)
			VALUES ('pt_stop', $1, 'didok', $1, ST_SetSRID(ST_MakePoint($2, 46.5), 4326)) RETURNING id`, name, lon).Scan(&id); err != nil {
			t.Fatal(err)
		}
		ids[name] = id
	}
	p := &Planner{DB: pool}

	// A day cannot end where the hike starts or ends.
	for _, name := range []string{"start", "end"} {
		if _, err := p.Split(ctx, legs, Request{Profile: "hike", Days: Days{N: 2}, Ends: []string{ids[name]}}); !errors.Is(err, ErrUnknownEnd) {
			t.Errorf("ending at the %s: err = %v", name, err)
		}
	}
	got, err := p.Split(ctx, legs, Request{Profile: "hike", Days: Days{N: 2}, Ends: []string{ids["middle"]}})
	if err != nil || len(got.Stages) != 2 {
		t.Fatalf("ending in the middle: %d stages, %v", len(got.Stages), err)
	}
}
