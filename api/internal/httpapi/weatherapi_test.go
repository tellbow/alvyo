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
				Date   string  `json:"date"`
				MaxC   float64 `json:"max_c"`
				Symbol int     `json:"symbol"`
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
	if w.Places[0].Days[0].Symbol != 6 {
		t.Errorf("symbol: %s", body)
	}
	// A day within the forecast: no climate; beyond it: its month's.
	for _, tc := range []struct {
		date string
		want bool
	}{{day(1), false}, {day(40), true}, {day(-3), false}} {
		_, body = c.do("GET", "/api/v1/routes/"+r.ID+"/weather?date="+tc.date, nil)
		var cw struct {
			Places []struct {
				Climate *struct {
					Month   int     `json:"month"`
					Station string  `json:"station"`
					MaxC    float64 `json:"max_c"`
				} `json:"climate"`
			} `json:"places"`
		}
		_ = json.Unmarshal(body, &cw)
		if got := cw.Places[0].Climate != nil; got != tc.want {
			t.Errorf("%s: climate %v: %s", tc.date, got, body)
		} else if got && (cw.Places[0].Climate.Station == "" || cw.Places[0].Climate.Month != int(now.AddDate(0, 0, 40).Month())) {
			t.Errorf("%s: %s", tc.date, body)
		}
	}
	if code, _ := s.client(t).do("GET", "/api/v1/routes/"+r.ID+"/weather", nil); code != http.StatusNotFound {
		t.Errorf("someone else's private route: %d", code)
	}
}

// A stage planned within the forecast has its day; one planned later the
// climate of its month.
func TestJourneyWeather(t *testing.T) {
	zurich, _ := time.LoadLocation("Europe/Zurich")
	now := time.Now().In(zurich)
	day := func(n int) string { return now.AddDate(0, 0, n).Format(time.DateOnly) }
	srv, _ := weathertest.Server(t, []weathertest.Point{
		{Type: "2", ID: "1", Name: "Tal", Height: 1000, Lon: 8.0, Lat: 46.5},
	}, []string{day(0), day(1)})
	forecast := &weather.Forecast{URL: srv.URL + "/c"}
	if err := forecast.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	s := newTestServerWith(t, func(d *Deps) { d.Weather = forecast })
	c := s.client(t)
	c.do("POST", "/api/v1/auth/signup", signupBody("hiker@example.ch", "hiker"))
	_, body := c.do("POST", "/api/v1/journeys", map[string]any{"title": "Weit voraus"})
	base := "/api/v1/journeys/" + decodeJourney(t, body).ID
	for range 2 {
		c.do("POST", base+"/stages", map[string]any{})
	}
	_, body = c.do("GET", base, nil)
	j := decodeJourney(t, body)
	for i, st := range j.StageList {
		if code, body := c.do("POST", base+"/stages/"+st.ID+"/route", stageRouteBody(8.0+float64(i)*0.002)); code != http.StatusOK {
			t.Fatalf("stage route: %d %s", code, body)
		}
		c.do("PATCH", base+"/stages/"+st.ID, map[string]any{"planned_date": day(1 + i*60)}, stageMatch(t, c, base, st.ID)...)
	}
	code, body := c.do("GET", base+"/weather", nil)
	var w struct {
		Stages []struct {
			Day *struct {
				Date string `json:"date"`
			} `json:"day"`
			Climate *struct {
				Month int `json:"month"`
			} `json:"climate"`
		} `json:"stages"`
	}
	if err := json.Unmarshal(body, &w); code != http.StatusOK || err != nil || len(w.Stages) != 2 {
		t.Fatalf("weather: %d %s", code, body)
	}
	if w.Stages[0].Day == nil || w.Stages[0].Climate != nil {
		t.Errorf("tomorrow: %s", body)
	}
	if w.Stages[1].Day != nil || w.Stages[1].Climate == nil || w.Stages[1].Climate.Month != int(now.AddDate(0, 0, 61).Month()) {
		t.Errorf("in two months: %s", body)
	}
}
