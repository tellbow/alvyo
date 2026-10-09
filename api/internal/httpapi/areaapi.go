package httpapi

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"slices"
	"time"

	"github.com/danielgtaylor/huma/v2"
	"golang.org/x/sync/errgroup"

	"github.com/tellbow/alvyo/api/internal/areas"
	"github.com/tellbow/alvyo/swiss/geo"
)

type areasOutput struct {
	Body struct {
		Areas   []areas.Area   `json:"areas"`
		Notices []areas.Notice `json:"notices" doc:"Closed trails and shooting on the way, from today on"`
	}
}

type lineAreasInput struct {
	Body struct {
		Line [][2]float64 `json:"line" minItems:"2" maxItems:"50000" doc:"[lon, lat] per point"`
	}
}

// crossedAreas returns the protected areas a line crosses and the notices
// (closures, shooting) on it from today on.
func crossedAreas(ctx context.Context, d Deps, line []geo.Point) ([]areas.Area, []areas.Notice, error) {
	found, err := d.Areas.Crossed(ctx, line)
	var notices []areas.Notice
	if err == nil {
		notices, err = d.Areas.Notices(ctx, line, time.Now().In(zurich))
	}
	if errors.Is(err, areas.ErrUnavailable) {
		slog.WarnContext(ctx, "protected areas", "err", err)
		return nil, nil, huma.Error503ServiceUnavailable("protected areas unavailable, please retry")
	}
	return found, notices, err
}

func registerAreas(api huma.API, d Deps) {
	tags := []string{"routing"}
	crossed := func(ctx context.Context, line []geo.Point) ([]areas.Area, []areas.Notice, error) {
		return crossedAreas(ctx, d, line)
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
		out.Body.Areas, out.Body.Notices, err = crossed(ctx, line)
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
		out.Body.Areas, out.Body.Notices, err = crossed(ctx, points(r.Line()))
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
		noticeByID := map[string]*areas.Notice{}
		var noticeOrder []string
		// Each stage asks geo.admin; a few at a time, not one after another.
		type result struct {
			found   []areas.Area
			notices []areas.Notice
		}
		results := make([]result, len(j.StageList))
		g, gctx := errgroup.WithContext(ctx)
		g.SetLimit(4)
		for i, st := range j.StageList {
			if st.Route == nil {
				continue
			}
			g.Go(func() error {
				found, notices, err := crossed(gctx, points(st.FullLine()))
				results[i] = result{found, notices}
				return err
			})
		}
		if err := g.Wait(); err != nil {
			return nil, err
		}
		for i, res := range results {
			found, notices := res.found, res.notices
			for _, n := range notices {
				key := n.Kind + "/" + n.ID
				if noticeByID[key] == nil {
					noticeByID[key] = &n
					noticeOrder = append(noticeOrder, key)
				}
				noticeByID[key].Stages = append(noticeByID[key].Stages, i+1)
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
		out.Body.Notices = []areas.Notice{}
		for _, k := range noticeOrder {
			out.Body.Notices = append(out.Body.Notices, *noticeByID[k])
		}
		return out, nil
	})
}
