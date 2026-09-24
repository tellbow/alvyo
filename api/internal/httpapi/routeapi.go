package httpapi

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"log/slog"
	"mime"
	"net/http"
	"strconv"
	"strings"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/odysgeh/api/internal/access"
	"github.com/tellbow/odysgeh/api/internal/auth"
	"github.com/tellbow/odysgeh/api/internal/dbq"
	"github.com/tellbow/odysgeh/api/internal/gpx"
	"github.com/tellbow/odysgeh/api/internal/og"
	"github.com/tellbow/odysgeh/api/internal/routes"
	"github.com/tellbow/odysgeh/api/internal/routing"
	"github.com/tellbow/odysgeh/swiss/geo"
)

// routeBodyLimit allows long multi-leg routes (each vertex carries elevation).
const routeBodyLimit = 16 << 20

type turnsOutput struct {
	Body struct {
		Turns []routing.Turn `json:"turns"`
	}
}

type routeOutput struct {
	ETag string `header:"ETag"`
	Body routeBody
}

type routeBody struct {
	routes.Route
	Role    string `json:"role" enum:"owner,editor,viewer"`
	CanEdit bool   `json:"can_edit"`
	// ShareToken is shown to the owner only; the link is /routes/{id}?t=token.
	ShareToken string `json:"share_token,omitempty"`
}

type createRouteInput struct {
	Body struct {
		Title       string          `json:"title" minLength:"1" maxLength:"120"`
		Description string          `json:"description,omitempty" maxLength:"5000"`
		Visibility  string          `json:"visibility,omitempty" enum:"private,unlisted,public" default:"private"`
		Tags        []string        `json:"tags,omitempty" maxItems:"20" doc:"At most 20, each up to 40 characters; repeats (ignoring case) are dropped"`
		Profile     string          `json:"profile" enum:"hike,alpine"`
		Anchors     []routes.Anchor `json:"anchors" minItems:"2" maxItems:"200"`
		Legs        []routing.Leg   `json:"legs" minItems:"1" maxItems:"199"`
	}
}

type routeIDInput struct {
	ID    string `path:"id" format:"uuid"`
	Token string `query:"t" doc:"Share token of an unlisted route"`
}

type shareTokenOutput struct {
	Body struct {
		ShareToken string `json:"share_token"`
	}
}

type updateRouteInput struct {
	ID      string `path:"id" format:"uuid"`
	IfMatch string `header:"If-Match" required:"true" doc:"Version (ETag) the change is based on"`
	Body    struct {
		Title       *string         `json:"title,omitempty" minLength:"1" maxLength:"120"`
		Description *string         `json:"description,omitempty" maxLength:"5000"`
		Visibility  *string         `json:"visibility,omitempty" enum:"private,unlisted,public"`
		Tags        []string        `json:"tags,omitempty" maxItems:"20" doc:"Replaces the tags; [] removes them. Not for stage routes, which have their journey's"`
		Profile     *string         `json:"profile,omitempty" enum:"hike,alpine"`
		Anchors     []routes.Anchor `json:"anchors,omitempty" maxItems:"200"`
		Legs        []routing.Leg   `json:"legs,omitempty" maxItems:"199"`
	}
}

type gpxOutput struct {
	ContentType        string `header:"Content-Type"`
	ContentDisposition string `header:"Content-Disposition"`
	Body               []byte
}

type imageOutput struct {
	ContentType  string `header:"Content-Type"`
	CacheControl string `header:"Cache-Control"`
	Body         []byte
}

type routeListOutput struct {
	Body struct {
		Routes []routes.Summary `json:"routes"`
	}
}

func registerRoutes(api huma.API, d Deps) {
	tags := []string{"routes"}
	store := d.Routes

	huma.Register(api, huma.Operation{
		OperationID: "create-route", Method: http.MethodPost, Path: "/routes",
		Summary: "Save a planned route", Tags: tags, DefaultStatus: http.StatusCreated, MaxBodyBytes: routeBodyLimit,
	}, func(ctx context.Context, in *createRouteInput) (*routeOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if err := checkPublish(u, in.Body.Visibility); err != nil {
			return nil, err
		}
		labels, err := normalizeTags(in.Body.Tags)
		if err != nil {
			return nil, err
		}
		r, err := store.Create(ctx, u.ID,
			routes.Meta{Title: strings.TrimSpace(in.Body.Title), Description: in.Body.Description, Visibility: in.Body.Visibility, Tags: labels},
			routes.Content{Profile: in.Body.Profile, Anchors: in.Body.Anchors, Legs: in.Body.Legs})
		if err != nil {
			return nil, routeError(err)
		}
		return routeResponse(r, access.Owner), nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "list-my-routes", Method: http.MethodGet, Path: "/routes",
		Summary: "The logged-in user's routes, most recently changed first", Tags: tags,
	}, func(ctx context.Context, _ *struct{}) (*routeListOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		list, err := store.ListByOwner(ctx, u.ID, 500)
		if err != nil {
			return nil, err
		}
		out := &routeListOutput{}
		out.Body.Routes = list
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-route", Method: http.MethodGet, Path: "/routes/{id}",
		Summary: "A route with its planner state", Tags: tags,
	}, func(ctx context.Context, in *routeIDInput) (*routeOutput, error) {
		r, role, err := loadRoute(ctx, d, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		return routeResponse(r, role), nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-route-gpx", Method: http.MethodGet, Path: "/routes/{id}/gpx",
		Summary: "Download a route as GPX 1.1", Tags: tags,
	}, func(ctx context.Context, in *routeIDInput) (*gpxOutput, error) {
		r, _, err := loadRoute(ctx, d, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		var buf bytes.Buffer
		if err := gpx.Write(&buf, gpx.Track{
			Name:        r.Title,
			Description: r.Description,
			Author:      r.OwnerUsername,
			Link:        d.PublicURL + "/routes/" + r.ID,
			Points:      r.Line(),
			Time:        r.UpdatedAt,
		}); err != nil {
			return nil, err
		}
		return &gpxOutput{
			ContentType:        "application/gpx+xml",
			ContentDisposition: mime.FormatMediaType("attachment", map[string]string{"filename": gpx.Filename(r.Title)}),
			Body:               buf.Bytes(),
		}, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-route-turns", Method: http.MethodGet, Path: "/routes/{id}/turns",
		Summary:     "Turns along a route, for spoken navigation",
		Description: "The route's line matched onto the path network. Where it does not follow the network, as GPS tracks and straight legs do not, there are no turns.",
		Tags:        tags,
	}, func(ctx context.Context, in *routeIDInput) (*turnsOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if !d.Limits.LegUser.Allow(u.ID.String()) {
			return nil, errTooMany
		}
		r, _, err := loadRoute(ctx, d, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		var line []geo.Point
		for _, c := range r.Line() {
			line = append(line, geo.Point{Lon: c[0], Lat: c[1]})
		}
		turns, err := d.Router.GraphHopper.Turns(ctx, line)
		if err != nil {
			slog.WarnContext(ctx, "turns failed", "route", r.ID, "err", err)
			return nil, huma.Error503ServiceUnavailable("routing unavailable, please retry")
		}
		out := &turnsOutput{}
		out.Body.Turns = turns
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-route-image", Method: http.MethodGet, Path: "/routes/{id}/og.png",
		Summary: "Preview image of a route for link previews (1200×630)", Tags: tags,
	}, func(ctx context.Context, in *routeIDInput) (*imageOutput, error) {
		r, _, err := loadRoute(ctx, d, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		b, err := d.Images.PNG(fmt.Sprintf("%s-%d", r.ID, r.Version), og.Card{
			Title:  r.Title,
			Stats:  cardStats(r.Totals),
			Points: r.Line(),
		})
		if err != nil {
			return nil, err
		}
		cache := "private, max-age=3600" // not in shared caches unless anyone may see it
		if r.Visibility == "public" && r.JourneyID == "" {
			cache = "public, max-age=3600"
		}
		return &imageOutput{ContentType: "image/png", CacheControl: cache, Body: b}, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "update-route", Method: http.MethodPatch, Path: "/routes/{id}",
		Summary:     "Change a route",
		Description: "Fails with 412 if the route changed since the version in If-Match. Anchors and legs must be sent together.",
		Tags:        tags, MaxBodyBytes: routeBodyLimit,
	}, func(ctx context.Context, in *updateRouteInput) (*routeOutput, error) {
		r, role, err := loadRoute(ctx, d, in.ID, "")
		if err != nil {
			return nil, err
		}
		if role < access.Editor {
			return nil, forbidden(access.Editor, "route")
		}
		version, err := strconv.Atoi(strings.Trim(strings.TrimPrefix(in.IfMatch, "W/"), `"`))
		if err != nil {
			return nil, huma.Error400BadRequest("If-Match must be the route version")
		}
		b := in.Body
		meta := r.Meta
		if b.Title != nil {
			meta.Title = strings.TrimSpace(*b.Title)
		}
		if b.Description != nil {
			meta.Description = *b.Description
		}
		if b.Visibility != nil && r.JourneyID != "" {
			return nil, huma.Error422UnprocessableEntity("a stage route has the visibility of its journey")
		}
		if b.Tags != nil && r.JourneyID != "" {
			return nil, huma.Error422UnprocessableEntity("a stage route has the tags of its journey")
		}
		if b.Tags != nil {
			if meta.Tags, err = normalizeTags(b.Tags); err != nil {
				return nil, err
			}
		}
		if b.Visibility != nil && *b.Visibility != r.Visibility && role < access.Owner {
			return nil, forbidden(access.Owner, "route")
		}
		if b.Visibility != nil && *b.Visibility != r.Visibility {
			u, _ := auth.UserFrom(ctx)
			if err := checkPublish(u, *b.Visibility); err != nil {
				return nil, err
			}
			meta.Visibility = *b.Visibility
		}
		var content *routes.Content
		switch {
		case b.Anchors != nil && b.Legs != nil:
			profile := r.Profile
			if b.Profile != nil {
				profile = *b.Profile
			}
			content = &routes.Content{Profile: profile, Anchors: b.Anchors, Legs: b.Legs}
		case b.Anchors != nil || b.Legs != nil || b.Profile != nil:
			return nil, huma.Error422UnprocessableEntity("anchors, legs and profile change together")
		}
		updated, err := store.Update(ctx, uuid.MustParse(r.ID), version, meta, content)
		if err != nil {
			return nil, routeError(err)
		}
		return routeResponse(updated, role), nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "delete-route", Method: http.MethodDelete, Path: "/routes/{id}",
		Summary: "Delete a route", Tags: tags, DefaultStatus: http.StatusNoContent,
	}, func(ctx context.Context, in *routeIDInput) (*struct{}, error) {
		r, role, err := loadRoute(ctx, d, in.ID, "")
		if err != nil {
			return nil, err
		}
		if role < access.Owner {
			return nil, forbidden(access.Owner, "route")
		}
		return nil, routeError(store.Delete(ctx, uuid.MustParse(r.ID)))
	})

	huma.Register(api, huma.Operation{
		OperationID: "rotate-route-link", Method: http.MethodPost, Path: "/routes/{id}/link/rotate",
		Summary: "Replace the share link; the old link stops working", Tags: tags,
	}, func(ctx context.Context, in *routeIDInput) (*shareTokenOutput, error) {
		r, role, err := loadRoute(ctx, d, in.ID, "")
		if err != nil {
			return nil, err
		}
		if role < access.Owner {
			return nil, forbidden(access.Owner, "route")
		}
		token, err := store.RotateShareToken(ctx, uuid.MustParse(r.ID))
		if err != nil {
			return nil, routeError(err)
		}
		out := &shareTokenOutput{}
		out.Body.ShareToken = token
		return out, nil
	})
}

func routeResponse(r routes.Route, role access.Role) *routeOutput {
	body := routeBody{Route: r, Role: role.String(), CanEdit: role >= access.Editor}
	if role == access.Owner && r.Visibility == "unlisted" && r.JourneyID == "" {
		body.ShareToken = r.ShareToken
	}
	return &routeOutput{ETag: strconv.Quote(strconv.Itoa(r.Version)), Body: body}
}

// checkPublish enforces that only verified accounts share routes beyond
// themselves (public or by link).
func checkPublish(u dbq.User, visibility string) error {
	if visibility != "private" && u.EmailVerifiedAt == nil {
		return huma.Error403Forbidden("confirm your e-mail address to publish routes")
	}
	return nil
}

// cardStats is the one-line summary on preview images.
func cardStats(t routes.Totals) string {
	sac := fmt.Sprintf("T%d", t.SACGrade)
	if t.SACMax > t.SACGrade {
		sac += fmt.Sprintf("–T%d", t.SACMax)
	}
	return fmt.Sprintf("%.1f km · %s · ↑ %.0f m ↓ %.0f m · %s",
		t.DistanceM/1000, og.Duration(t.DurationS), t.AscentM, t.DescentM, sac)
}

func routeError(err error) error {
	switch {
	case err == nil:
		return nil
	case errors.Is(err, routes.ErrNotFound):
		return huma.Error404NotFound("route not found")
	case errors.Is(err, routes.ErrVersion):
		return huma.Error412PreconditionFailed("the route was changed in the meantime; reload it")
	case errors.Is(err, routes.ErrInvalid):
		return huma.Error422UnprocessableEntity(err.Error())
	}
	return err
}
