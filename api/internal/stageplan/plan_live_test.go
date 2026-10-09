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
		url = "postgres://alvyo:alvyo@localhost:5432/alvyo?sslmode=disable"
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

// TestSuggestLive: Thun to Zermatt in five days goes over the Lötschenpass
// directly; one of the others over the Gemmi, as hikers usually go.
func TestSuggestLive(t *testing.T) {
	url := os.Getenv("ALVYO_DATABASE_URL")
	if url == "" {
		url = "postgres://alvyo:alvyo@localhost:5432/alvyo?sslmode=disable"
	}
	pool, err := pgxpool.New(context.Background(), url)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	p := &Planner{
		Router: &routing.Router{
			GraphHopper: &routing.GraphHopper{URL: "http://localhost:8989"},
			Elevation:   &elevation.GeoAdmin{UserAgent: "alvyo-test"},
			Trails:      &routing.TrailMatcher{DB: pool},
		},
		DB: pool,
	}
	thun := geo.Point{Lon: 7.62970, Lat: 46.75480}
	zermatt := geo.Point{Lon: 7.74750, Lat: 46.02440}
	gemmi := geo.Point{Lon: 7.61280, Lat: 46.39850}

	start := time.Now()
	sugs, err := p.Suggest(context.Background(), Request{
		Points: []geo.Point{thun, zermatt}, Profile: "hike", Days: Days{N: 5}, Kinds: []string{"hut", "hotel"},
	})
	if err != nil {
		t.Fatal(err)
	}
	overGemmi := false
	for i, s := range sugs {
		line := "Thun"
		km := 0.0
		for _, st := range s.Proposal.Stages {
			km += st.Totals.DistanceM / 1000
			if st.EndPlace != nil {
				line += " → " + st.EndPlace.Name
			}
			for _, l := range st.Legs {
				for _, c := range l.Coordinates {
					if geo.Distance(gemmi, geo.Point{Lon: c[0], Lat: c[1]}) < 1500 {
						overGemmi = true
					}
				}
			}
		}
		t.Logf("suggestion %d: %.0f km, %d days: %s → Zermatt", i+1, km, len(s.Proposal.Stages), line)
	}
	t.Logf("suggested in %v", time.Since(start))
	if len(sugs) < 2 {
		t.Fatalf("%d suggestions", len(sugs))
	}
	if !overGemmi {
		t.Error("none over the Gemmi")
	}
}
