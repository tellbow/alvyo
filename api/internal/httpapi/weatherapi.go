package httpapi

import (
	"context"
	"errors"
	"net/http"
	"slices"
	"time"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/routes"
	"github.com/tellbow/alvyo/api/internal/weather"
)

type weatherPlace struct {
	Roles []string              `json:"roles" doc:"start, top (the highest point), end"`
	Point weather.ForecastPoint `json:"point" doc:"MeteoSwiss's forecast point"`
	Days  []weather.ForecastDay `json:"days" doc:"From today on"`
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
	// the next nine days.
	Day *weather.ForecastDay `json:"day,omitempty"`
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
	ends := func(r routes.Route) [][3]float64 {
		line := r.Line()
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

	huma.Register(api, huma.Operation{
		OperationID: "route-weather", Method: http.MethodGet, Path: "/routes/{id}/weather",
		Summary:     "MeteoSwiss's forecast at a route's start, highest point and end",
		Description: "For each, the forecast point nearby of the most similar height; the next days. 503 before the first forecast is loaded.",
		Tags:        tags,
	}, func(ctx context.Context, in *routeIDInput) (*routeWeatherOutput, error) {
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
		for i, c := range ends(r) {
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
				Days: slices.DeleteFunc(slices.Clone(days), func(x weather.ForecastDay) bool { return x.Date < day }),
			})
		}
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "journey-weather", Method: http.MethodGet, Path: "/journeys/{id}/weather",
		Summary: "MeteoSwiss's forecast at each stage's highest point, for its planned day",
		Tags:    tags,
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
			r, err := d.Routes.Get(ctx, uuid.MustParse(st.Route.ID))
			if err != nil {
				return nil, routeError(err)
			}
			e := ends(r)
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
			out.Body.Stages = append(out.Body.Stages, sw)
		}
		return out, nil
	})
}
