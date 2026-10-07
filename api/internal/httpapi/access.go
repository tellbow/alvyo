package httpapi

import (
	"context"
	"errors"
	"strings"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/access"
	"github.com/tellbow/alvyo/api/internal/auth"
	"github.com/tellbow/alvyo/api/internal/collections"
	"github.com/tellbow/alvyo/api/internal/grants"
	"github.com/tellbow/alvyo/api/internal/journeys"
	"github.com/tellbow/alvyo/api/internal/routes"
)

// roleOn completes res with the caller's grant on the item and returns the
// caller's role.
func (d Deps) roleOn(ctx context.Context, res access.Resource, kind grants.Kind, id uuid.UUID, token string) (access.Role, error) {
	u, loggedIn := auth.UserFrom(ctx)
	if !loggedIn {
		return res.RoleOf("", token), nil
	}
	if d.Grants != nil && u.ID.String() != res.OwnerID {
		g, err := d.Grants.RoleOf(ctx, kind, id, u)
		if err != nil {
			return access.None, err
		}
		res.Grant = g
	}
	return res.RoleOf(u.ID.String(), token), nil
}

// collectionPass reads a token that opens an item through a collection one
// sees without an invitation: "c.{collection id}", with ".{its share token}"
// when it is unlisted.
func collectionPass(token string) (id uuid.UUID, collectionToken string, ok bool) {
	rest, ok := strings.CutPrefix(token, "c.")
	if !ok {
		return uuid.Nil, "", false
	}
	rawID, collectionToken, _ := strings.Cut(rest, ".")
	id, err := uuid.Parse(rawID)
	return id, collectionToken, err == nil
}

// viaCollection returns the role the caller holds on an item through
// collections: through those they own or were invited to, and through the
// one in token (at most editor) if it shares the item.
func (d Deps) viaCollection(ctx context.Context, kind grants.Kind, id uuid.UUID, token string) (access.Role, error) {
	if d.Collections == nil {
		return access.None, nil
	}
	role := access.None
	if _, loggedIn := auth.UserFrom(ctx); loggedIn {
		var err error
		if role, err = d.Collections.RoleOf(ctx, string(kind), id, viewer(ctx)); err != nil || role >= access.Editor {
			return role, err
		}
	}
	cid, ctoken, ok := collectionPass(token)
	if !ok {
		return role, nil
	}
	res, err := d.Collections.Access(ctx, cid)
	if errors.Is(err, collections.ErrNotFound) {
		return role, nil
	}
	if err != nil {
		return access.None, err
	}
	passRole, err := d.roleOn(ctx, res, grants.Collection, cid, ctoken)
	if err != nil || passRole <= role {
		return role, err
	}
	shares, err := d.Collections.Shares(ctx, cid, string(kind), id)
	if err != nil || !shares {
		return role, err
	}
	return min(passRole, access.Editor), nil
}

// roleWith is roleOn, raised by collections that share the item.
func (d Deps) roleWith(ctx context.Context, res access.Resource, kind grants.Kind, id uuid.UUID, token string) (access.Role, error) {
	role, err := d.roleOn(ctx, res, kind, id, token)
	if err != nil || role >= access.Editor {
		return role, err
	}
	via, err := d.viaCollection(ctx, kind, id, token)
	return max(role, via), err
}

// loadRoute returns a route the caller may see, with their role. Stage routes
// follow their journey's visibility, share token, grants and collections.
// Routes the caller may not see are reported as missing.
func loadRoute(ctx context.Context, d Deps, rawID, token string) (routes.Route, access.Role, error) {
	id, err := uuid.Parse(rawID)
	if err != nil {
		return routes.Route{}, access.None, huma.Error404NotFound("route not found")
	}
	r, err := d.Routes.Get(ctx, id)
	if err != nil {
		return routes.Route{}, access.None, routeError(err)
	}
	res := access.Resource{OwnerID: r.OwnerID, Visibility: r.Visibility, ShareToken: r.ShareToken}
	kind, grantID := grants.Route, id
	if r.JourneyID != "" && d.Journeys != nil {
		grantID, kind = uuid.MustParse(r.JourneyID), grants.Journey
		if res, err = d.Journeys.Access(ctx, grantID); err != nil {
			return routes.Route{}, access.None, journeyError(err)
		}
	}
	role, err := d.roleWith(ctx, res, kind, grantID, token)
	if err != nil {
		return routes.Route{}, access.None, err
	}
	if role == access.None {
		return routes.Route{}, access.None, huma.Error404NotFound("route not found")
	}
	if role == access.Viewer {
		r = r.ForOthers() // a recorded hike without its start and end
	}
	return r, role, nil
}

// loadJourney returns a journey the caller may see, with their role; others
// get 404.
func loadJourney(ctx context.Context, d Deps, rawID, token string) (journeys.Journey, access.Role, error) {
	id, err := uuid.Parse(rawID)
	if err != nil {
		return journeys.Journey{}, access.None, huma.Error404NotFound("journey not found")
	}
	j, err := d.Journeys.Get(ctx, id)
	if err != nil {
		return journeys.Journey{}, access.None, journeyError(err)
	}
	res := access.Resource{OwnerID: j.OwnerID, Visibility: j.Visibility, ShareToken: j.ShareToken}
	role, err := d.roleWith(ctx, res, grants.Journey, id, token)
	if err != nil {
		return journeys.Journey{}, access.None, err
	}
	if role == access.None {
		return journeys.Journey{}, access.None, huma.Error404NotFound("journey not found")
	}
	return j, role, nil
}

// journeyAs loads a journey the caller holds at least role on: 404 if they
// cannot see it, 403 if they can but lack the role.
func journeyAs(ctx context.Context, d Deps, rawID string, need access.Role) (journeys.Journey, access.Role, error) {
	j, role, err := loadJourney(ctx, d, rawID, "")
	if err != nil {
		return j, role, err
	}
	if role < need {
		return j, role, forbidden(need, "journey")
	}
	return j, role, nil
}

func forbidden(need access.Role, what string) error {
	if need == access.Owner {
		return huma.Error403Forbidden("only the owner can do this with the " + what)
	}
	return huma.Error403Forbidden("you may only view this " + what)
}
