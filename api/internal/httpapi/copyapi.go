package httpapi

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/access"
	"github.com/tellbow/alvyo/api/internal/journeys"
	"github.com/tellbow/alvyo/api/internal/routes"
)

// registerCopies lets anyone logged in take a route or journey they can see
// as their own private one to change («Als eigene Route bearbeiten»).
func registerCopies(api huma.API, d Deps) {
	huma.Register(api, huma.Operation{
		OperationID: "copy-route", Method: http.MethodPost, Path: "/routes/{id}/copy",
		Summary: "Copy a route as one's own private route", Tags: []string{"routes"}, DefaultStatus: http.StatusCreated,
	}, func(ctx context.Context, in *routeIDInput) (*routeOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		r, role, err := loadRoute(ctx, d, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		// Others see a recorded hike without its start and end.
		if r.Hike != nil && role != access.Owner {
			return nil, huma.Error403Forbidden("recorded hikes of others cannot be copied")
		}
		c, err := d.Routes.Create(ctx, u.ID, routes.Meta{Title: r.Title, Description: r.Description, Visibility: "private"},
			routes.Content{Profile: r.Profile, Anchors: r.Anchors, Legs: r.Legs})
		if err != nil {
			return nil, routeError(err)
		}
		return routeResponse(c, access.Owner), nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "copy-journey", Method: http.MethodPost, Path: "/journeys/{id}/copy",
		Summary:     "Copy a journey as one's own private journey",
		Description: "The stages with their titles, routes and transfers; not their dates, marks, notes or places to stay.",
		Tags:        []string{"journeys"}, DefaultStatus: http.StatusCreated,
	}, func(ctx context.Context, in *journeyIDInput) (*journeyOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		j, _, err := loadJourney(ctx, d, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		c, err := d.Journeys.Create(ctx, u.ID, journeys.Meta{Title: j.Title, Description: j.Description, Visibility: "private"})
		if err != nil {
			return nil, err
		}
		cid := uuid.MustParse(c.ID)
		if err := copyStages(ctx, d, j, cid, u.ID); err != nil {
			_ = d.Journeys.Delete(context.WithoutCancel(ctx), cid)
			return nil, err
		}
		if c, err = d.Journeys.Get(ctx, cid); err != nil {
			return nil, err
		}
		return journeyResponse(c, access.Owner), nil
	})
}

// copyStages gives the journey to the stages of j, in order.
func copyStages(ctx context.Context, d Deps, j journeys.Journey, to, owner uuid.UUID) error {
	for _, st := range j.StageList {
		transfer := ""
		if st.TransferBefore != nil {
			transfer = *st.TransferBefore
		}
		stage, err := d.Journeys.AddStageID(ctx, to, owner, journeys.NewStage{Title: st.Title, TransferBefore: transfer})
		if err != nil {
			return err
		}
		if st.Route == nil {
			continue
		}
		r, err := d.Routes.Get(ctx, uuid.MustParse(st.Route.ID))
		if err != nil {
			return err
		}
		if _, err := d.Journeys.SetStageRoute(ctx, to, stage, owner, r.Title,
			routes.Content{Profile: r.Profile, Anchors: r.Anchors, Legs: r.Legs}); err != nil {
			return err
		}
	}
	return nil
}
