package httpapi

import (
	"context"
	"net/http"
	"strconv"
	"strings"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/access"
	"github.com/tellbow/alvyo/api/internal/auth"
	"github.com/tellbow/alvyo/api/internal/routes"
)

type revisionsOutput struct {
	Body struct {
		Revisions []routes.Revision `json:"revisions" doc:"Newest first, at most 20"`
	}
}

type revisionInput struct {
	ID      string `path:"id" format:"uuid"`
	Version int    `path:"version" minimum:"1"`
}

type revisionOutput struct {
	Body struct {
		Route    routeBody       `json:"route" doc:"The route with the line it had then"`
		Revision routes.Revision `json:"revision"`
	}
}

type restoreInput struct {
	ID      string `path:"id" format:"uuid"`
	Version int    `path:"version" minimum:"1"`
	IfMatch string `header:"If-Match" required:"true" doc:"The route's current version (ETag)"`
}

// registerRevisions: the earlier lines of a route, for those who may change
// it (they also show what a recorded hike hides from others).
func registerRevisions(api huma.API, d Deps) {
	tags := []string{"routes"}
	editable := func(ctx context.Context, rawID string) (routes.Route, access.Role, error) {
		r, role, err := loadRoute(ctx, d, rawID, "")
		if err == nil && role < access.Editor {
			err = forbidden(access.Editor, "route")
		}
		return r, role, err
	}
	// revision is the route with an earlier line.
	revision := func(ctx context.Context, r routes.Route, version int) (routes.Route, routes.Revision, error) {
		rv, c, err := d.Routes.RevisionContent(ctx, uuid.MustParse(r.ID), version)
		if err != nil {
			return r, rv, routeError(err)
		}
		legs, totals, err := routes.Check(c)
		if err != nil {
			return r, rv, err
		}
		r.Profile, r.Anchors, r.Legs, r.Totals = c.Profile, c.Anchors, legs, totals
		return r, rv, nil
	}

	huma.Register(api, huma.Operation{
		OperationID: "list-route-revisions", Method: http.MethodGet, Path: "/routes/{id}/revisions",
		Summary: "Earlier versions of a route's line", Tags: tags,
	}, func(ctx context.Context, in *routeIDInput) (*revisionsOutput, error) {
		r, _, err := editable(ctx, in.ID)
		if err != nil {
			return nil, err
		}
		out := &revisionsOutput{}
		out.Body.Revisions, err = d.Routes.Revisions(ctx, uuid.MustParse(r.ID))
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-route-revision", Method: http.MethodGet, Path: "/routes/{id}/revisions/{version}",
		Summary: "A route with the line it had at an earlier version", Tags: tags,
	}, func(ctx context.Context, in *revisionInput) (*revisionOutput, error) {
		r, role, err := editable(ctx, in.ID)
		if err != nil {
			return nil, err
		}
		old, rv, err := revision(ctx, r, in.Version)
		if err != nil {
			return nil, err
		}
		out := &revisionOutput{}
		out.Body.Route = routeResponse(old, role).Body
		out.Body.Revision = rv
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "restore-route-revision", Method: http.MethodPost, Path: "/routes/{id}/revisions/{version}/restore",
		Summary:     "Make an earlier line the route's line again",
		Description: "The line replaced becomes a revision itself. Fails with 412 if the route changed since the version in If-Match.",
		Tags:        tags,
	}, func(ctx context.Context, in *restoreInput) (*routeOutput, error) {
		r, role, err := editable(ctx, in.ID)
		if err != nil {
			return nil, err
		}
		current, err := strconv.Atoi(strings.Trim(strings.TrimPrefix(in.IfMatch, "W/"), `"`))
		if err != nil {
			return nil, huma.Error400BadRequest("If-Match must be the route version")
		}
		old, _, err := revision(ctx, r, in.Version)
		if err != nil {
			return nil, err
		}
		u, _ := auth.UserFrom(ctx)
		c := routes.Content{Profile: old.Profile, Anchors: old.Anchors, Legs: old.Legs}
		updated, err := d.Routes.Update(ctx, uuid.MustParse(r.ID), current, r.Meta, &c, u.ID)
		if err != nil {
			return nil, routeError(err)
		}
		return routeResponse(updated, role), nil
	})
}
