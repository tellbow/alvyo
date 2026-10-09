//go:build live

package routing

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tellbow/alvyo/swiss/elevation"
	"github.com/tellbow/alvyo/swiss/geo"
)

// TestLegLive runs against the dev stack: GraphHopper on :8989, the compose
// database with swissTLM3D imported, and the real geo.admin service.
// Run with: go test -tags live ./internal/routing/
func TestLegLive(t *testing.T) {
	url := os.Getenv("ALVYO_DATABASE_URL")
	if url == "" {
		url = "postgres://alvyo:alvyo@localhost:5432/alvyo?sslmode=disable"
	}
	pool, err := pgxpool.New(context.Background(), url)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	r := &Router{
		GraphHopper: &GraphHopper{URL: "http://localhost:8989"},
		Elevation:   &elevation.GeoAdmin{UserAgent: "alvyo-test"},
		Trails:      &TrailMatcher{DB: pool},
	}
	gaflei := geo.Point{Lon: 9.54280, Lat: 47.14472}
	sargans := geo.Point{Lon: 9.44563, Lat: 47.04488}

	for _, req := range []LegRequest{
		{From: gaflei, To: sargans, Profile: "hike"},
		{From: gaflei, To: geo.Point{Lon: 9.55, Lat: 47.14}, Straight: true},
	} {
		start := time.Now()
		leg, err := r.Leg(context.Background(), req)
		if err != nil {
			t.Fatalf("%+v: %v", req, err)
		}
		t.Logf("straight=%v: %.1f km, +%.0f/-%.0f m, %ds, SAC T%d–T%d, trails %v in %v",
			req.Straight, leg.DistanceM/1000, leg.AscentM, leg.DescentM, leg.DurationS, leg.SAC.Grade, leg.SAC.Max, leg.Trails, time.Since(start))
	}
}

// TestAcrossTheBorderLive: legs 15 km into the neighbouring countries, with
// heights from geo.admin (needs the graph of `make osm-fetch` since
// requirement 31).
func TestAcrossTheBorderLive(t *testing.T) {
	pool, err := pgxpool.New(context.Background(), "postgres://alvyo:alvyo@localhost:5432/alvyo?sslmode=disable")
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	r := &Router{
		GraphHopper: &GraphHopper{URL: "http://localhost:8989"},
		Elevation:   &elevation.GeoAdmin{UserAgent: "alvyo-test"},
		Trails:      &TrailMatcher{DB: pool},
	}
	for name, req := range map[string]LegRequest{
		"Martigny – Chamonix":       {From: geo.Point{Lon: 7.0333, Lat: 46.0833}, To: geo.Point{Lon: 6.8694, Lat: 45.9237}, Profile: "hike"},
		"Zermatt – Breuil-Cervinia": {From: geo.Point{Lon: 7.72, Lat: 45.985}, To: geo.Point{Lon: 7.63, Lat: 45.936}, Profile: "alpine"},
		"Basel – Lörrach":           {From: geo.Point{Lon: 7.58, Lat: 47.55}, To: geo.Point{Lon: 7.66, Lat: 47.62}, Profile: "hike"},
	} {
		leg, err := r.Leg(context.Background(), req)
		if err != nil {
			t.Errorf("%s: %v", name, err)
			continue
		}
		t.Logf("%s: %.1f km, +%.0f m", name, leg.DistanceM/1000, leg.AscentM)
	}
}
