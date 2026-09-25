//go:build live

package stageplan

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tellbow/alvyo/api/internal/routing"
	"github.com/tellbow/alvyo/swiss/elevation"
	"github.com/tellbow/alvyo/swiss/geo"
)

// TestPlanLive runs against the dev stack: GraphHopper on :8989, the compose
// database with swissTLM3D and the places imported, and geo.admin.
// Run with: go test -tags live ./internal/stageplan/
func TestPlanLive(t *testing.T) {
	url := os.Getenv("ALVYO_DATABASE_URL")
	if url == "" {
		url = "postgres://odysgeh:odysgeh@localhost:5432/odysgeh?sslmode=disable"
	}
	pool, err := pgxpool.New(context.Background(), url)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	p := &Planner{
		Router: &routing.Router{
			GraphHopper: &routing.GraphHopper{URL: "http://localhost:8989", Client: nil},
			Elevation:   &elevation.GeoAdmin{UserAgent: "alvyo-test"},
			Trails:      &routing.TrailMatcher{DB: pool},
		},
		DB: pool,
	}
	gaflei := geo.Point{Lon: 9.54280, Lat: 47.14472}
	elm := geo.Point{Lon: 9.17060, Lat: 46.91860}
	sargans := geo.Point{Lon: 9.44563, Lat: 47.04488}
	weisstannen := geo.Point{Lon: 9.33260, Lat: 46.99200}

	start := time.Now()
	prop, err := p.Plan(context.Background(), Request{
		Points: []geo.Point{gaflei, elm}, Profile: "hike", Days: Days{N: 3},
	})
	if err != nil {
		t.Fatal(err)
	}
	for i, st := range prop.Stages {
		name := "Elm"
		if st.EndPlace != nil {
			name = st.EndPlace.Name + " (" + st.EndPlace.Kind + ")"
		}
		t.Logf("day %d: %.1f km, ↑%.0f m, %s → %s", i+1, st.Totals.DistanceM/1000, st.Totals.AscentM,
			time.Duration(st.Totals.DurationS)*time.Second, name)
	}
	t.Logf("planned in %v", time.Since(start))
	if len(prop.Stages) != 3 {
		t.Fatalf("%d stages", len(prop.Stages))
	}
	for i, want := range []geo.Point{sargans, weisstannen} {
		end := prop.Stages[i].EndPlace
		if d := geo.Distance(want, geo.Point{Lon: end.At[0], Lat: end.At[1]}); d > 4000 {
			t.Errorf("day %d ends at %s, %.1f km from the Via Alpina stage end", i+1, end.Name, d/1000)
		}
	}
}
