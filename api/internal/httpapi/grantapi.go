package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/access"
	"github.com/tellbow/alvyo/api/internal/collections"
	"github.com/tellbow/alvyo/api/internal/grants"
	"github.com/tellbow/alvyo/api/internal/journeys"
	"github.com/tellbow/alvyo/api/internal/routes"
)

type grantsOutput struct {
	Body struct {
		Grants []grants.Grant `json:"grants"`
	}
}

type itemInput struct {
	ID string `path:"id" format:"uuid"`
}

type inviteInput struct {
	ID   string `path:"id" format:"uuid"`
	Body struct {
		Username string `json:"username,omitempty" maxLength:"31" doc:"Invite an account (either this or email)"`
		Email    string `json:"email,omitempty" format:"email" maxLength:"254" doc:"Invite an address; it applies once someone signs in with it"`
		Role     string `json:"role" enum:"viewer,editor"`
	}
}

type grantRoleInput struct {
	ID      string `path:"id" format:"uuid"`
	GrantID string `path:"grant" format:"uuid"`
	Body    struct {
		Role string `json:"role" enum:"viewer,editor"`
	}
}

type grantIDInput struct {
	ID      string `path:"id" format:"uuid"`
	GrantID string `path:"grant" format:"uuid"`
}

type sharedOutput struct {
	Body struct {
		Routes      []routes.Shared      `json:"routes"`
		Journeys    []journeys.Shared    `json:"journeys"`
		Collections []collections.Shared `json:"collections"`
	}
}

// grantItem resolves a route or journey for grant management.
type grantItem struct {
	kind   grants.Kind
	path   string // "/routes" or "/journeys"
	opName string // "route" or "journey"
	// load returns the item as a grant target and the caller's role.
	load func(ctx context.Context, rawID string) (grants.Target, access.Role, error)
}

func registerGrants(api huma.API, d Deps) {
	items := []grantItem{
		{kind: grants.Route, path: "/routes", opName: "route",
			load: func(ctx context.Context, rawID string) (grants.Target, access.Role, error) {
				r, role, err := loadRoute(ctx, d, rawID, "")
				if err != nil {
					return grants.Target{}, role, err
				}
				if r.JourneyID != "" {
					return grants.Target{}, role, huma.Error422UnprocessableEntity("a stage route is shared with its journey")
				}
				return grants.Target{Kind: grants.Route, ID: uuid.MustParse(r.ID), Title: r.Title}, role, nil
			}},
		{kind: grants.Journey, path: "/journeys", opName: "journey",
			load: func(ctx context.Context, rawID string) (grants.Target, access.Role, error) {
				j, role, err := loadJourney(ctx, d, rawID, "")
				if err != nil {
					return grants.Target{}, role, err
				}
				return grants.Target{Kind: grants.Journey, ID: uuid.MustParse(j.ID), Title: j.Title}, role, nil
			}},
		{kind: grants.Collection, path: "/collections", opName: "collection",
			load: func(ctx context.Context, rawID string) (grants.Target, access.Role, error) {
				c, role, err := loadCollection(ctx, d, rawID, "")
				if err != nil {
					return grants.Target{}, role, err
				}
				return grants.Target{Kind: grants.Collection, ID: uuid.MustParse(c.ID), Title: c.Title}, role, nil
			}},
	}
	for _, it := range items {
		registerGrantItem(api, d, it)
	}

	huma.Register(api, huma.Operation{
		OperationID: "list-shared-with-me", Method: http.MethodGet, Path: "/shared",
		Summary: "Routes, journeys and collections others shared with the logged-in user", Tags: []string{"sharing"},
	}, func(ctx context.Context, _ *struct{}) (*sharedOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		uid, email := grants.Grantee(u)
		out := &sharedOutput{}
		if out.Body.Routes, err = d.Routes.ListSharedWith(ctx, uid, email, 500); err != nil {
			return nil, err
		}
		if out.Body.Journeys, err = d.Journeys.ListSharedWith(ctx, uid, email); err != nil {
			return nil, err
		}
		if out.Body.Collections, err = d.Collections.ListSharedWith(ctx, viewer(ctx)); err != nil {
			return nil, err
		}
		return out, nil
	})
}

func registerGrantItem(api huma.API, d Deps, it grantItem) {
	tags := []string{"sharing"}
	owned := func(ctx context.Context, rawID string) (grants.Target, error) {
		t, role, err := it.load(ctx, rawID)
		if err != nil {
			return t, err
		}
		if role < access.Owner {
			return t, forbidden(access.Owner, it.opName)
		}
		return t, nil
	}
	list := func(ctx context.Context, t grants.Target) (*grantsOutput, error) {
		gs, err := d.Grants.List(ctx, t)
		if err != nil {
			return nil, err
		}
		out := &grantsOutput{}
		out.Body.Grants = gs
		return out, nil
	}

	huma.Register(api, huma.Operation{
		OperationID: "list-" + it.opName + "-grants", Method: http.MethodGet, Path: it.path + "/{id}/grants",
		Summary: "Who the " + it.opName + " is shared with (owner only)", Tags: tags,
	}, func(ctx context.Context, in *itemInput) (*grantsOutput, error) {
		t, err := owned(ctx, in.ID)
		if err != nil {
			return nil, err
		}
		return list(ctx, t)
	})

	huma.Register(api, huma.Operation{
		OperationID: "invite-to-" + it.opName, Method: http.MethodPost, Path: it.path + "/{id}/grants",
		Summary:     "Share the " + it.opName + " with an account or an e-mail address",
		Description: "Inviting someone who already has access changes their role. New invitations are announced by e-mail.",
		Tags:        tags,
	}, func(ctx context.Context, in *inviteInput) (*grantsOutput, error) {
		t, err := owned(ctx, in.ID)
		if err != nil {
			return nil, err
		}
		u, _ := requireUser(ctx)
		if u.EmailVerifiedAt == nil {
			return nil, huma.Error403Forbidden("confirm your e-mail address to share")
		}
		b := in.Body
		b.Username, b.Email = strings.TrimSpace(b.Username), strings.TrimSpace(b.Email)
		if (b.Username == "") == (b.Email == "") {
			return nil, huma.Error422UnprocessableEntity("give either a username or an e-mail address")
		}
		if !d.Limits.Invite.Allow(u.ID.String()) {
			return nil, huma.Error429TooManyRequests("too many invitations; try again later")
		}
		err = d.Grants.Invite(ctx, t, u, grants.Invite{Username: b.Username, Email: b.Email, Role: b.Role})
		switch {
		case errors.Is(err, grants.ErrNoUser):
			return nil, huma.Error422UnprocessableEntity("there is no user with this name")
		case errors.Is(err, grants.ErrSelf):
			return nil, huma.Error422UnprocessableEntity("you cannot invite yourself")
		case errors.Is(err, grants.ErrTooMany):
			return nil, huma.Error422UnprocessableEntity("too many people have access already")
		case err != nil:
			return nil, err
		}
		return list(ctx, t)
	})

	huma.Register(api, huma.Operation{
		OperationID: "change-" + it.opName + "-grant", Method: http.MethodPatch, Path: it.path + "/{id}/grants/{grant}",
		Summary: "Change someone's role", Tags: tags,
	}, func(ctx context.Context, in *grantRoleInput) (*grantsOutput, error) {
		t, err := owned(ctx, in.ID)
		if err != nil {
			return nil, err
		}
		if err := d.Grants.SetRole(ctx, t, uuid.MustParse(in.GrantID), in.Body.Role); err != nil {
			return nil, grantError(err)
		}
		return list(ctx, t)
	})

	huma.Register(api, huma.Operation{
		OperationID: "revoke-" + it.opName + "-grant", Method: http.MethodDelete, Path: it.path + "/{id}/grants/{grant}",
		Summary: "Stop sharing with someone", Tags: tags,
	}, func(ctx context.Context, in *grantIDInput) (*grantsOutput, error) {
		t, err := owned(ctx, in.ID)
		if err != nil {
			return nil, err
		}
		if err := d.Grants.Delete(ctx, t, uuid.MustParse(in.GrantID)); err != nil {
			return nil, grantError(err)
		}
		return list(ctx, t)
	})

	huma.Register(api, huma.Operation{
		OperationID: "leave-" + it.opName, Method: http.MethodDelete, Path: it.path + "/{id}/access",
		Summary: "Remove the " + it.opName + " from what is shared with me", Tags: tags,
		DefaultStatus: http.StatusNoContent,
	}, func(ctx context.Context, in *itemInput) (*struct{}, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		t, _, err := it.load(ctx, in.ID)
		if err != nil {
			return nil, err
		}
		return nil, grantError(d.Grants.Leave(ctx, t, u))
	})
}

func grantError(err error) error {
	if errors.Is(err, grants.ErrNotFound) {
		return huma.Error404NotFound("not shared with this person")
	}
	return err
}
