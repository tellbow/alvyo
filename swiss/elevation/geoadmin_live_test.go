//go:build live

package elevation

import (
	"context"
	"testing"

	"github.com/tellbow/alvyo/swiss/geo"
)

// TestGeoAdminLive checks the real service, including Liechtenstein coverage.
// Run with: go test -tags live ./elevation/
func TestGeoAdminLive(t *testing.T) {
	pts := []geo.Point{
		{Lon: 9.5428, Lat: 47.1447}, // Gaflei (FL), ~1480 m
		{Lon: 9.4456, Lat: 47.0449}, // Sargans (CH), ~480 m
	}
	dense, _ := geo.Densify(pts, 20)
	h, err := (&GeoAdmin{UserAgent: "alvyo-test"}).Sample(context.Background(), dense)
	if err != nil {
		t.Fatal(err)
	}
	if h[0] < 1300 || h[0] > 1700 {
		t.Errorf("Gaflei %.1f m", h[0])
	}
	if last := h[len(h)-1]; last < 400 || last > 600 {
		t.Errorf("Sargans %.1f m", last)
	}
	t.Logf("%d samples, Gaflei %.1f m, Sargans %.1f m", len(h), h[0], h[len(h)-1])
}
