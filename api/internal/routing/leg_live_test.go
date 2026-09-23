//go:build live

package routing

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tellbow/odysgeh/swiss/elevation"
	"github.com/tellbow/odysgeh/swiss/geo"
)

// TestLegLive runs against the dev stack: GraphHopper on :8989, the compose
// database with swissTLM3D imported, and the real geo.admin service.
// Run with: go test -tags live ./internal/routing/
func TestLegLive(t *testing.T) {
	url := os.Getenv("ODYSGEH_DATABASE_URL")
	if url == "" {
		url = "postgres://odysgeh:odysgeh@localhost:5432/odysgeh?sslmode=disable"
	}
	pool, err := pgxpool.New(context.Background(), url)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	r := &Router{
		GraphHopper: &GraphHopper{URL: "http://localhost:8989"},
		Elevation:   &elevation.GeoAdmin{UserAgent: "odysgeh-test"},
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
