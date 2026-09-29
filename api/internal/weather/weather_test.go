package weather

import (
	"context"
	"errors"
	"testing"

	"github.com/tellbow/alvyo/api/internal/weather/weathertest"
)

func TestForecast(t *testing.T) {
	ctx := context.Background()
	srv, files := weathertest.Server(t, []weathertest.Point{
		{Type: "2", ID: "1", Name: "Grindelwald", Height: 1034, Lon: 8.0414, Lat: 46.6242},
		{Type: "3", ID: "7", Name: "Männlichen", Height: 2230, Lon: 7.9412, Lat: 46.6128},
		{Type: "1", ID: "9", Name: "Zürich", Height: 556, Lon: 8.565, Lat: 47.378},
	}, []string{"2026-09-29", "2026-09-28"})
	f := &Forecast{URL: srv.URL + "/c"}
	if _, _, err := f.At(8.0, 46.6, 2000); !errors.Is(err, ErrNoForecast) {
		t.Errorf("before loading: %v", err)
	}
	if err := f.Refresh(ctx); err != nil {
		t.Fatal(err)
	}
	if f.Run().Format("15:04") != "18:00" {
		t.Errorf("run %v: the complete one", f.Run())
	}

	// High up near Grindelwald: Männlichen, not the village nearer by.
	p, days, err := f.At(8.02, 46.62, 2100)
	if err != nil || p.Name != "Männlichen" || p.Height != 2230 {
		t.Fatalf("high: %+v %v", p, err)
	}
	if len(days) != 2 || days[0].Date != "2026-09-28" || days[1] != (ForecastDay{Date: "2026-09-29", MinC: 4.5, MaxC: 12, RainMM: 3.2, RainLoMM: 0.4, RainHiMM: 9.8, Symbol: 6}) {
		t.Errorf("days: %+v", days)
	}
	if p, _, _ = f.At(8.03, 46.62, 1050); p.Name != "Grindelwald" {
		t.Errorf("low: %+v", p)
	}
	if _, _, err := f.At(10.4, 46.6, 1500); !errors.Is(err, ErrNoForecast) {
		t.Errorf("nothing within 15 km: %v", err)
	}

	// The same run is not loaded again.
	n := *files
	if err := f.Refresh(ctx); err != nil || *files != n {
		t.Errorf("reloaded: %v, %d files", err, *files-n)
	}
}
