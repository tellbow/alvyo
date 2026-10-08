package httpapi

import (
	"context"
	"errors"
	"net/http"
	"slices"
	"time"

	"github.com/danielgtaylor/huma/v2"

	"github.com/tellbow/alvyo/api/internal/weather"
)

type weatherPlace struct {
	Roles []string              `json:"roles" doc:"start, top (the highest point), end"`
	Point weather.ForecastPoint `json:"point" doc:"MeteoSwiss's forecast point"`
	Days  []weather.ForecastDay `json:"days" doc:"From today on"`
	// Climate is what is usual in the month of the date asked for, when
	// that date lies beyond the forecast.
	Climate *weather.Climate `json:"climate,omitempty"`
}

type routeWeatherInput struct {
	ID    string `path:"id" format:"uuid"`
	Token string `query:"t" doc:"Share token of an unlisted route"`
	Date  string `query:"date" format:"date" doc:"A day beyond the forecast: the climate normals of its month come along"`
}

type routeWeatherOutput struct {
	Body struct {
		Run    time.Time      `json:"run" doc:"When MeteoSwiss made the forecast"`
		Places []weatherPlace `json:"places"`
	}
}

type stageWeather struct {
	Stage int                   `json:"stage" doc:"From 1"`
	Point weather.ForecastPoint `json:"point" doc:"At the stage's highest point"`
	// Day is the forecast of the stage's planned day, if it has one within
	// the next nine days; Climate what is usual in its month, if it lies
	// beyond them.
	Day     *weather.ForecastDay `json:"day,omitempty"`
	Climate *weather.Climate     `json:"climate,omitempty"`
	// PlannedDate is the stage's planned day, if it has one.
	PlannedDate string `json:"planned_date,omitempty" format:"date"`
}

type journeyWeatherOutput struct {
	Body struct {
		Run    time.Time      `json:"run"`
		Stages []stageWeather `json:"stages"`
	}
}

var errNoWeather = huma.Error503ServiceUnavailable("weather unavailable, please retry")

func registerWeather(api huma.API, d Deps) {
	tags := []string{"weather"}
	zurich, err := time.LoadLocation("Europe/Zurich")
	if err != nil {
		panic(err) // cannot happen: time/tzdata is linked in
	}
	today := func() string { return time.Now().In(zurich).Format(time.DateOnly) }
	// ends returns start, highest point and end of a line.
	ends := func(line [][3]float64) [][3]float64 {
		if len(line) == 0 {
			return nil
		}
		top := line[0]
		for _, c := range line {
			if c[2] > top[2] {
				top = c
			}
		}
		return [][3]float64{line[0], top, line[len(line)-1]}
	}
	// climate is what is usual at c in the month of date, if date lies
	// after the forecast's last day (and so after today).
	climate := func(c [3]float64, date string, days []weather.ForecastDay) *weather.Climate {
		t, err := time.Parse(time.DateOnly, date)
		if err != nil || date < today() || (len(days) > 0 && date <= days[len(days)-1].Date) {
			return nil
		}
		if cl, ok := weather.ClimateAt(c[0], c[1], c[2], int(t.Month())); ok {
			return &cl
		}
		return nil
	}

	huma.Register(api, huma.Operation{
		OperationID: "route-weather", Method: http.MethodGet, Path: "/routes/{id}/weather",
		Summary:     "MeteoSwiss's forecast at a route's start, highest point and end",
		Description: "For each, the forecast point nearby of the most similar height; the next days, and for a `date` beyond them the climate normals of its month. 503 before the first forecast is loaded.",
		Tags:        tags,
	}, func(ctx context.Context, in *routeWeatherInput) (*routeWeatherOutput, error) {
		r, _, err := loadRoute(ctx, d, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		if d.Weather == nil || d.Weather.Run().IsZero() {
			return nil, errNoWeather
		}
		out := &routeWeatherOutput{}
		out.Body.Run = d.Weather.Run()
		out.Body.Places = []weatherPlace{}
		day := today()
		for i, c := range ends(r.Line()) {
			p, days, err := d.Weather.At(c[0], c[1], c[2])
			if errors.Is(err, weather.ErrNoForecast) {
				continue // across the border, beyond the forecast points
			}
			role := [...]string{"start", "top", "end"}[i]
			if n := len(out.Body.Places); n > 0 && out.Body.Places[n-1].Point == p {
				out.Body.Places[n-1].Roles = append(out.Body.Places[n-1].Roles, role)
				continue
			}
			out.Body.Places = append(out.Body.Places, weatherPlace{
				Roles: []string{role}, Point: p,
				Days:    slices.DeleteFunc(slices.Clone(days), func(x weather.ForecastDay) bool { return x.Date < day }),
				Climate: climate(c, in.Date, days),
			})
		}
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "journey-weather", Method: http.MethodGet, Path: "/journeys/{id}/weather",
		Summary:     "MeteoSwiss's forecast at each stage's highest point, for its planned day",
		Description: "A planned day beyond the forecast has the climate normals of its month instead.",
		Tags:        tags,
	}, func(ctx context.Context, in *journeyIDInput) (*journeyWeatherOutput, error) {
		j, _, err := loadJourney(ctx, d, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		if d.Weather == nil || d.Weather.Run().IsZero() {
			return nil, errNoWeather
		}
		out := &journeyWeatherOutput{}
		out.Body.Run = d.Weather.Run()
		out.Body.Stages = []stageWeather{}
		for i, st := range j.StageList {
			if st.Route == nil {
				continue
			}
			e := ends(st.FullLine())
			if e == nil {
				continue
			}
			p, days, err := d.Weather.At(e[1][0], e[1][1], e[1][2])
			if err != nil {
				continue
			}
			sw := stageWeather{Stage: i + 1, Point: p}
			for _, x := range days {
				if st.PlannedDate != nil && x.Date == *st.PlannedDate {
					sw.Day = &x
				}
			}
			if st.PlannedDate != nil {
				sw.PlannedDate = *st.PlannedDate
				sw.Climate = climate(e[1], *st.PlannedDate, days)
			}
			out.Body.Stages = append(out.Body.Stages, sw)
		}
		return out, nil
	})
}
