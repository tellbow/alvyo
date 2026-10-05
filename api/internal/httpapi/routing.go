package httpapi

import (
	"context"
	"errors"
	"log/slog"
	"net/http"

	"github.com/danielgtaylor/huma/v2"

	"github.com/tellbow/alvyo/api/internal/routing"
	"github.com/tellbow/alvyo/swiss/geo"
)

// Point is a WGS84 position inside the covered area (the box around
// Switzerland, Liechtenstein and the 15 km around them).
type Point struct {
	Lon float64 `json:"lon" minimum:"5.7" maximum:"10.7"`
	Lat float64 `json:"lat" minimum:"45.65" maximum:"47.95"`
}

func (p Point) geo() geo.Point { return geo.Point{Lon: p.Lon, Lat: p.Lat} }

type legInput struct {
	Body struct {
		From     Point  `json:"from"`
		To       Point  `json:"to"`
		Profile  string `json:"profile,omitempty" enum:"hike,alpine" default:"hike" doc:"hike: up to SAC T3; alpine: up to T6"`
		Straight bool   `json:"straight,omitempty" doc:"Draw a straight line instead of following paths"`
		Through  *Point `json:"through,omitempty" doc:"Where the line was dragged onto another path: the leg takes the path closest to it"`
	}
}

type legOutput struct{ Body routing.Leg }

type alternativesInput struct {
	Body struct {
		From    Point  `json:"from"`
		To      Point  `json:"to"`
		Profile string `json:"profile,omitempty" enum:"hike,alpine" default:"hike"`
	}
}

type alternativesOutput struct {
	Body struct {
		Ways [][][2]float64 `json:"ways" doc:"The ways between the two points, the shortest first; [lon, lat] per point"`
	}
}

type reachInput struct {
	Body struct {
		From    Point  `json:"from"`
		Profile string `json:"profile,omitempty" enum:"hike,alpine" default:"hike"`
	}
}

type reachOutput struct {
	Body struct {
		Areas []routing.ReachArea `json:"areas" doc:"Reached within 2, 4 and 8 hours at the user's pace, the smallest first"`
	}
}

// reachSlots: isochrones search GraphHopper for seconds; two at a time
// leave it free for planning.
var reachSlots = make(chan struct{}, 2)

type profile struct {
	ID     string `json:"id"`
	MaxSAC int    `json:"max_sac" doc:"Hardest SAC grade the profile routes over"`
}

type profilesOutput struct {
	Body struct {
		Profiles []profile `json:"profiles"`
	}
}

func registerRouting(api huma.API, d Deps) {
	tags := []string{"routing"}

	huma.Register(api, huma.Operation{
		OperationID: "get-routing-profiles", Method: http.MethodGet, Path: "/routing/profiles",
		Summary: "Available routing profiles", Tags: tags,
	}, func(context.Context, *struct{}) (*profilesOutput, error) {
		out := &profilesOutput{}
		out.Body.Profiles = []profile{{ID: "hike", MaxSAC: 3}, {ID: "alpine", MaxSAC: 6}}
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "route-leg", Method: http.MethodPost, Path: "/routing/leg",
		Summary:     "Compute the leg between two anchors",
		Description: "Follows hiking paths (or a straight line) and returns the geometry with swissALTI3D elevation, Swiss hiking time, SAC grade and breakdowns.",
		Tags:        tags,
	}, func(ctx context.Context, in *legInput) (*legOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if !d.Limits.LegUser.Allow(u.ID.String()) {
			return nil, errTooMany
		}
		req := routing.LegRequest{
			From: in.Body.From.geo(), To: in.Body.To.geo(), Profile: in.Body.Profile, Straight: in.Body.Straight,
		}
		if in.Body.Through != nil {
			p := in.Body.Through.geo()
			req.Through = &p
		}
		leg, err := d.Router.Leg(ctx, req)
		if err := legError(ctx, err); err != nil {
			return nil, err
		}
		return &legOutput{Body: leg}, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "route-reach", Method: http.MethodPost, Path: "/routing/reach",
		Summary:     "How far one gets from a point",
		Description: "The areas reached on foot within 2, 4 and 8 hours at the user's pace, the ways timed by their slope like the Swiss hiking time. Approximate: an area is the outline around what is reached.",
		Tags:        tags,
	}, func(ctx context.Context, in *reachInput) (*reachOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if !d.Limits.ReachUser.Allow(u.ID.String()) {
			return nil, errTooMany
		}
		select {
		case reachSlots <- struct{}{}:
			defer func() { <-reachSlots }()
		case <-ctx.Done():
			return nil, ctx.Err()
		}
		areas, err := d.Router.GraphHopper.Reach(ctx, in.Body.From.geo(), in.Body.Profile, float64(u.SpeedFactor))
		if err := legError(ctx, err); err != nil {
			return nil, err
		}
		out := &reachOutput{}
		out.Body.Areas = areas
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "route-alternatives", Method: http.MethodPost, Path: "/routing/alternatives",
		Summary:     "The ways between two anchors",
		Description: "What a leg can be dragged onto: the paths GraphHopper offers, the shortest first. A leg with `through` on one of them takes that one.",
		Tags:        tags,
	}, func(ctx context.Context, in *alternativesInput) (*alternativesOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if !d.Limits.LegUser.Allow(u.ID.String()) {
			return nil, errTooMany
		}
		ways, err := d.Router.Alternatives(ctx, in.Body.From.geo(), in.Body.To.geo(), in.Body.Profile)
		if err := legError(ctx, err); err != nil {
			return nil, err
		}
		out := &alternativesOutput{}
		out.Body.Ways = make([][][2]float64, len(ways))
		for i, w := range ways {
			out.Body.Ways[i] = make([][2]float64, len(w))
			for j, p := range w {
				out.Body.Ways[i][j] = [2]float64{p.Lon, p.Lat}
			}
		}
		return out, nil
	})
}

// legError is how a routing error is answered; nil without one.
func legError(ctx context.Context, err error) error {
	switch {
	case errors.Is(err, routing.ErrPointNotFound), errors.Is(err, routing.ErrOutOfBounds):
		return huma.Error422UnprocessableEntity("no path near this point")
	case errors.Is(err, routing.ErrNoConnection):
		return huma.Error422UnprocessableEntity("no connection between these points with this profile")
	case errors.Is(err, routing.ErrElevation):
		slog.WarnContext(ctx, "leg elevation failed", "err", err)
		return huma.Error503ServiceUnavailable("elevation service unavailable, please retry")
	}
	return err
}
