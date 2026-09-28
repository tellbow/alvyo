package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/tellbow/alvyo/api/internal/weather"
	"github.com/tellbow/alvyo/api/internal/weather/weathertest"
)

func TestWeather(t *testing.T) {
	zurich, _ := time.LoadLocation("Europe/Zurich")
	now := time.Now().In(zurich)
	day := func(n int) string { return now.AddDate(0, 0, n).Format(time.DateOnly) }
	// newRouteBody runs east from (8.0, 46.5), climbing from 1000 m.
	srv, _ := weathertest.Server(t, []weathertest.Point{
		{Type: "2", ID: "1", Name: "Tal", Height: 1000, Lon: 8.0, Lat: 46.5},
		{Type: "3", ID: "2", Name: "Gipfel", Height: 3000, Lon: 8.02, Lat: 46.5},
	}, []string{day(-1), day(0), day(1)})
	forecast := &weather.Forecast{URL: srv.URL + "/c"}
	s := newTestServerWith(t, func(d *Deps) { d.Weather = forecast })
	c := s.client(t)
	c.do("POST", "/api/v1/auth/signup", signupBody("hiker@example.ch", "hiker"))
	_, body := c.do("POST", "/api/v1/routes", newRouteBody("Gratweg", "private"))
	var r savedRoute
	_ = json.Unmarshal(body, &r)

	if code, _ := c.do("GET", "/api/v1/routes/"+r.ID+"/weather", nil); code != http.StatusServiceUnavailable {
		t.Errorf("before the first forecast: %d", code)
	}
	if err := forecast.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	code, body := c.do("GET", "/api/v1/routes/"+r.ID+"/weather", nil)
	var w struct {
		Places []struct {
			Roles []string `json:"roles"`
			Point struct {
				Name string `json:"name"`
			} `json:"point"`
			Days []struct {
				Date string  `json:"date"`
				MaxC float64 `json:"max_c"`
			} `json:"days"`
		} `json:"places"`
	}
	if err := json.Unmarshal(body, &w); code != http.StatusOK || err != nil {
		t.Fatalf("weather: %d %s", code, body)
	}
	// A short route low down: one point for start, top and end; from today.
	if len(w.Places) != 1 || len(w.Places[0].Roles) != 3 || w.Places[0].Point.Name != "Tal" ||
		len(w.Places[0].Days) != 2 || w.Places[0].Days[0].Date != day(0) || w.Places[0].Days[0].MaxC != 12 {
		t.Errorf("weather: %s", body)
	}
	if code, _ := s.client(t).do("GET", "/api/v1/routes/"+r.ID+"/weather", nil); code != http.StatusNotFound {
		t.Errorf("someone else's private route: %d", code)
	}
}
