package httpapi

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"slices"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/odysgeh/api/internal/areas"
	"github.com/tellbow/odysgeh/swiss/geo"
)

type areasOutput struct {
	Body struct {
		Areas []areas.Area `json:"areas"`
	}
}

type lineAreasInput struct {
	Body struct {
		Line [][2]float64 `json:"line" minItems:"2" maxItems:"50000" doc:"[lon, lat] per point"`
	}
}

func registerAreas(api huma.API, d Deps) {
	tags := []string{"routing"}
	crossed := func(ctx context.Context, line []geo.Point) ([]areas.Area, error) {
		found, err := d.Areas.Crossed(ctx, line)
		if errors.Is(err, areas.ErrUnavailable) {
			slog.WarnContext(ctx, "protected areas", "err", err)
			return nil, huma.Error503ServiceUnavailable("protected areas unavailable, please retry")
		}
		return found, err
	}
	points := func(line [][3]float64) []geo.Point {
		pts := make([]geo.Point, len(line))
		for i, c := range line {
			pts[i] = geo.Point{Lon: c[0], Lat: c[1]}
		}
		return pts
	}

	huma.Register(api, huma.Operation{
		OperationID: "line-areas", Method: http.MethodPost, Path: "/routing/areas",
		Summary:     "The protected areas a line crosses",
		Description: "Wildlife rest areas (the Swiss National Park among them) and federal hunting reserves, from BAFU via geo.admin.",
		Tags:        tags,
	}, func(ctx context.Context, in *lineAreasInput) (*areasOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if !d.Limits.LegUser.Allow(u.ID.String()) {
			return nil, errTooMany
		}
		line := make([]geo.Point, len(in.Body.Line))
		for i, c := range in.Body.Line {
			line[i] = geo.Point{Lon: c[0], Lat: c[1]}
		}
		out := &areasOutput{}
		out.Body.Areas, err = crossed(ctx, line)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "route-areas", Method: http.MethodGet, Path: "/routes/{id}/areas",
		Summary: "The protected areas a route crosses", Tags: tags,
	}, func(ctx context.Context, in *routeIDInput) (*areasOutput, error) {
		r, _, err := loadRoute(ctx, d, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		out := &areasOutput{}
		out.Body.Areas, err = crossed(ctx, points(r.Line()))
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "journey-areas", Method: http.MethodGet, Path: "/journeys/{id}/areas",
		Summary: "The protected areas a journey's stages cross, with the stages", Tags: tags,
	}, func(ctx context.Context, in *journeyIDInput) (*areasOutput, error) {
		j, _, err := loadJourney(ctx, d, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		byID := map[string]*areas.Area{}
		var order []string
		for i, st := range j.StageList {
			if st.Route == nil {
				continue
			}
			r, err := d.Routes.Get(ctx, uuid.MustParse(st.Route.ID))
			if err != nil {
				return nil, routeError(err)
			}
			found, err := crossed(ctx, points(r.Line()))
			if err != nil {
				return nil, err
			}
			for _, a := range found {
				key := a.Kind + "/" + a.ID
				if byID[key] == nil {
					a.Stages = nil
					byID[key] = &a
					order = append(order, key)
				}
				if !slices.Contains(byID[key].Stages, i+1) {
					byID[key].Stages = append(byID[key].Stages, i+1)
				}
			}
		}
		out := &areasOutput{}
		out.Body.Areas = []areas.Area{}
		for _, k := range order {
			out.Body.Areas = append(out.Body.Areas, *byID[k])
		}
		return out, nil
	})
}
