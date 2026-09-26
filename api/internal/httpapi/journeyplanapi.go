package httpapi

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/routing"
	"github.com/tellbow/alvyo/api/internal/stageplan"
	"github.com/tellbow/alvyo/swiss/geo"
)

type planJourneyInput struct {
	Body struct {
		Points      []Point  `json:"points" minItems:"2" maxItems:"20" doc:"Start, points to pass, destination"`
		Profile     string   `json:"profile,omitempty" enum:"hike,alpine" default:"hike"`
		Days        int      `json:"days,omitempty" minimum:"0" maximum:"60" doc:"Number of days; or hours_per_day"`
		HoursPerDay float64  `json:"hours_per_day,omitempty" minimum:"0" maximum:"16" doc:"Hiking time per day (Swiss hiking time); or days"`
		MinHours    float64  `json:"min_hours,omitempty" minimum:"0" maximum:"16" doc:"With max_hours instead of days or hours_per_day: as few days as fit between the two"`
		MaxHours    float64  `json:"max_hours,omitempty" minimum:"0" maximum:"20" doc:"No day longer if possible; 0: 1.25 × the time per day"`
		Kinds       []string `json:"kinds,omitempty" enum:"hut,hotel,campsite,pt_stop" doc:"Preferred places for the nights; all if none"`
		Ends        []string `json:"ends,omitempty" maxItems:"59" doc:"Place ids to end the days at instead (from a proposal's earlier and later)"`
	}
}

// Resolve refuses a plan without days or hours, and ends that are no ids.
func (in *planJourneyInput) Resolve(huma.Context) []error {
	b := in.Body
	errs := daysErrors(b.Days, b.HoursPerDay, b.MinHours, b.MaxHours)
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

type suggestJourneysInput struct {
	Body struct {
		Points      []Point  `json:"points" minItems:"2" maxItems:"20" doc:"Start, points to pass, destination"`
		Profile     string   `json:"profile,omitempty" enum:"hike,alpine" default:"hike"`
		Days        int      `json:"days,omitempty" minimum:"0" maximum:"60" doc:"Number of days; or hours_per_day"`
		HoursPerDay float64  `json:"hours_per_day,omitempty" minimum:"0" maximum:"16" doc:"Hiking time per day (Swiss hiking time); or days"`
		MinHours    float64  `json:"min_hours,omitempty" minimum:"0" maximum:"16" doc:"With max_hours instead of days or hours_per_day: as few days as fit between the two"`
		MaxHours    float64  `json:"max_hours,omitempty" minimum:"0" maximum:"20" doc:"No day longer if possible; 0: 1.25 × the time per day"`
		Kinds       []string `json:"kinds,omitempty" enum:"hut,hotel,campsite,pt_stop" doc:"Preferred places for the nights; all if none"`
	}
}

// Resolve refuses suggestions without days or hours.
func (in *suggestJourneysInput) Resolve(huma.Context) []error {
	b := in.Body
	return daysErrors(b.Days, b.HoursPerDay, b.MinHours, b.MaxHours)
}

// daysErrors: days, hours per day, or the least and the most per day.
func daysErrors(days int, hours, minHours, maxHours float64) []error {
	switch {
	case minHours > 0 && (maxHours == 0 || minHours > maxHours):
		return []error{&huma.ErrorDetail{Location: "body.min_hours", Message: "give max_hours, at least min_hours"}}
	case days == 0 && hours == 0 && minHours == 0:
		return []error{&huma.ErrorDetail{Location: "body.days", Message: "give days, hours_per_day, or min_hours and max_hours"}}
	}
	return nil
}

// askedDays is what the planner is asked for.
func askedDays(days int, hours, minHours, maxHours float64) stageplan.Days {
	return stageplan.Days{N: days, TargetS: hours * 3600, MinS: minHours * 3600, MaxS: maxHours * 3600}
}

type suggestion struct {
	Points   []Point            `json:"points" doc:"The points asked for with the place passed; for POST /journeys/plan with ends, to move this way's nights"`
	Via      string             `json:"via" doc:"The village or hut the way passes, to tell the ways apart; empty for the direct way"`
	Proposal stageplan.Proposal `json:"proposal"`
}

type suggestJourneysOutput struct {
	Body struct {
		Suggestions []suggestion `json:"suggestions"`
	}
}

// planError gives the planner's errors to the client.
func planError(ctx context.Context, err error) error {
	switch {
	case errors.Is(err, routing.ErrPointNotFound), errors.Is(err, routing.ErrOutOfBounds):
		return huma.Error422UnprocessableEntity("no path near one of the points")
	case errors.Is(err, routing.ErrNoConnection):
		return huma.Error422UnprocessableEntity("no connection between the points with this profile")
	case errors.Is(err, stageplan.ErrUnknownEnd):
		return huma.Error422UnprocessableEntity(err.Error())
	case errors.Is(err, routing.ErrElevation):
		slog.WarnContext(ctx, "plan elevation failed", "err", err)
		return huma.Error503ServiceUnavailable("elevation service unavailable, please retry")
	}
	return err
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
			Days: askedDays(b.Days, b.HoursPerDay, b.MinHours, b.MaxHours),
		}
		for _, p := range b.Points {
			req.Points = append(req.Points, geo.Point{Lon: p.Lon, Lat: p.Lat})
		}
		proposal, err := planner.Plan(ctx, req)
		if err != nil {
			return nil, planError(ctx, err)
		}
		return &planJourneyOutput{Body: proposal}, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "suggest-journeys", Method: http.MethodPost, Path: "/journeys/suggest",
		Summary: "Suggest multi-day hikes on different ways",
		Description: "Up to four ways between the points, through different valleys and over different passes, " +
			"each split into days as by POST /journeys/plan, shortest first. Where two ways pass the same village " +
			"they tend to share the night there (the same end_place id), where one can change from one to the other. " +
			"Nothing is saved.",
		Tags: []string{"journeys"},
	}, func(ctx context.Context, in *suggestJourneysInput) (*suggestJourneysOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		// Up to four plans at once.
		if !d.Limits.Import.AllowN(u.ID.String(), 4) {
			return nil, huma.Error429TooManyRequests("too many plans; try again in a few minutes")
		}
		b := in.Body
		req := stageplan.Request{
			Profile: b.Profile, Kinds: b.Kinds,
			Days: askedDays(b.Days, b.HoursPerDay, b.MinHours, b.MaxHours),
		}
		for _, p := range b.Points {
			req.Points = append(req.Points, geo.Point{Lon: p.Lon, Lat: p.Lat})
		}
		sugs, err := planner.Suggest(ctx, req)
		if err != nil {
			return nil, planError(ctx, err)
		}
		out := &suggestJourneysOutput{}
		out.Body.Suggestions = []suggestion{}
		for _, sg := range sugs {
			s := suggestion{Via: sg.Via, Proposal: sg.Proposal}
			for _, p := range sg.Points {
				s.Points = append(s.Points, Point{Lon: p.Lon, Lat: p.Lat})
			}
			out.Body.Suggestions = append(out.Body.Suggestions, s)
		}
		return out, nil
	})
}
