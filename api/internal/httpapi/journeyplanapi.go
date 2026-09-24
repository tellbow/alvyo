package httpapi

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/odysgeh/api/internal/routing"
	"github.com/tellbow/odysgeh/api/internal/stageplan"
	"github.com/tellbow/odysgeh/swiss/geo"
)

type planJourneyInput struct {
	Body struct {
		Points      []Point  `json:"points" minItems:"2" maxItems:"20" doc:"Start, points to pass, destination"`
		Profile     string   `json:"profile,omitempty" enum:"hike,alpine" default:"hike"`
		Days        int      `json:"days,omitempty" minimum:"0" maximum:"60" doc:"Number of days; or hours_per_day"`
		HoursPerDay float64  `json:"hours_per_day,omitempty" minimum:"0" maximum:"16" doc:"Hiking time per day (Swiss hiking time); or days"`
		MaxHours    float64  `json:"max_hours,omitempty" minimum:"0" maximum:"20" doc:"No day longer if possible; 0: 1.25 × the time per day"`
		Kinds       []string `json:"kinds,omitempty" enum:"hut,hotel,campsite,pt_stop" doc:"Preferred places for the nights; all if none"`
		Ends        []string `json:"ends,omitempty" maxItems:"59" doc:"Place ids to end the days at instead (from a proposal's earlier and later)"`
	}
}

// Resolve refuses a plan without days or hours, and ends that are no ids.
func (in *planJourneyInput) Resolve(huma.Context) []error {
	var errs []error
	if in.Body.Days == 0 && in.Body.HoursPerDay == 0 {
		errs = append(errs, &huma.ErrorDetail{Location: "body.days", Message: "give days or hours_per_day"})
	}
	for i, id := range in.Body.Ends {
		if _, err := uuid.Parse(id); err != nil {
			errs = append(errs, &huma.ErrorDetail{Location: fmt.Sprintf("body.ends[%d]", i), Message: "not a place id", Value: id})
		}
	}
	return errs
}

type planJourneyOutput struct {
	Body stageplan.Proposal
}

func registerJourneyPlan(api huma.API, d Deps) {
	planner := &stageplan.Planner{Router: d.Router, DB: d.DB}

	huma.Register(api, huma.Operation{
		OperationID: "plan-journey", Method: http.MethodPost, Path: "/journeys/plan",
		Summary: "Propose the stages of a multi-day hike",
		Description: "Routes the whole way and ends the days where one can sleep (huts, hotels, campsites) or travel home " +
			"(stops), close to the time per day. Nothing is saved: POST /journeys with the stages does.",
		Tags: []string{"journeys"},
	}, func(ctx context.Context, in *planJourneyInput) (*planJourneyOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		// Like an import: the whole way is routed and its elevation sampled.
		if !d.Limits.Import.Allow(u.ID.String()) {
			return nil, huma.Error429TooManyRequests("too many plans; try again in a few minutes")
		}
		b := in.Body
		req := stageplan.Request{
			Profile: b.Profile, Kinds: b.Kinds, Ends: b.Ends,
			Days: stageplan.Days{N: b.Days, TargetS: b.HoursPerDay * 3600, MaxS: b.MaxHours * 3600},
		}
		for _, p := range b.Points {
			req.Points = append(req.Points, geo.Point{Lon: p.Lon, Lat: p.Lat})
		}
		proposal, err := planner.Plan(ctx, req)
		switch {
		case errors.Is(err, routing.ErrPointNotFound), errors.Is(err, routing.ErrOutOfBounds):
			return nil, huma.Error422UnprocessableEntity("no path near one of the points")
		case errors.Is(err, routing.ErrNoConnection):
			return nil, huma.Error422UnprocessableEntity("no connection between the points with this profile")
		case errors.Is(err, stageplan.ErrUnknownEnd):
			return nil, huma.Error422UnprocessableEntity(err.Error())
		case errors.Is(err, routing.ErrElevation):
			slog.WarnContext(ctx, "plan elevation failed", "err", err)
			return nil, huma.Error503ServiceUnavailable("elevation service unavailable, please retry")
		case err != nil:
			return nil, err
		}
		return &planJourneyOutput{Body: proposal}, nil
	})
}
