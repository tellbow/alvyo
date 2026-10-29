package httpapi

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"

	"github.com/tellbow/alvyo/api/internal/steep"
	"github.com/tellbow/alvyo/swiss/geo"
)

type steepOutput struct {
	Body steep.Steepness
}

func registerSteep(api huma.API, d Deps) {
	huma.Register(api, huma.Operation{
		OperationID: "route-steepness", Method: http.MethodGet, Path: "/routes/{id}/steepness",
		Summary:     "How steep the terrain is along a route",
		Description: "The stretches on terrain from 25°, 30° and 35° (swissALTI3D, measured over 20 m every 10 m) and how much is steeper than 30°; known in Switzerland only.",
		Tags:        []string{"routes"},
	}, func(ctx context.Context, in *routeIDInput) (*steepOutput, error) {
		r, _, err := loadRoute(ctx, d, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		line := r.Line()
		pts := make([]geo.Point, len(line))
		for i, c := range line {
			pts[i] = geo.Point{Lon: c[0], Lat: c[1]}
		}
		if len(pts) > 1 && geo.CumulativeDistance(pts)[len(pts)-1] > steep.MaxLineM {
			return nil, huma.Error422UnprocessableEntity("line: too long")
		}
		out := &steepOutput{}
		out.Body, err = steep.Of(ctx, d.Terrain, pts)
		return out, err
	})
}
