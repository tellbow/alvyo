//go:build live

package weather

import (
	"context"
	"testing"
)

// TestForecastLive loads the real latest run.
// Run with: go test -tags live ./internal/weather/
func TestForecastLive(t *testing.T) {
	f := &Forecast{UserAgent: "alvyo-test"}
	if err := f.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	p, days, err := f.At(8.0115, 46.6649, 2757) // the Reeti above Grindelwald
	if err != nil || len(days) < 5 {
		t.Fatalf("%+v %d days %v", p, len(days), err)
	}
	t.Logf("run %v: %s (%.0f m): %+v", f.Run(), p.Name, p.Height, days[1])
}
