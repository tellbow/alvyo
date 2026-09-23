package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/danielgtaylor/huma/v2"

	"github.com/tellbow/odysgeh/api/internal/community"
	"github.com/tellbow/odysgeh/api/internal/discover"
	"github.com/tellbow/odysgeh/api/internal/journeys"
	"github.com/tellbow/odysgeh/api/internal/routes"
)

type discoverInput struct {
	BBox        string `query:"bbox" required:"true" doc:"The map view: west,south,east,north (WGS84)" example:"7.9,46.55,8.1,46.7"`
	Kind        string `query:"kind" enum:"route,journey" doc:"Only routes or only journeys"`
	SACMax      int    `query:"sac_max" minimum:"0" maximum:"6" doc:"Hardest SAC grade allowed; 0 for any"`
	DurationMin int    `query:"duration_min" minimum:"0" doc:"Minimum hiking time (s); for journeys of the longest stage"`
	DurationMax int    `query:"duration_max" minimum:"0" doc:"Maximum hiking time (s); for journeys of the longest stage"`
}

type discoverOutput struct {
	Body struct {
		Items []discover.Item `json:"items"`
		More  bool            `json:"more" doc:"There are more results than shown: zoom in or narrow the filters"`
	}
}

type profileInput struct {
	Username string `path:"username"`
}

type profileOutput struct {
	Body struct {
		Username    string             `json:"username"`
		DisplayName string             `json:"display_name"`
		Since       time.Time          `json:"since" doc:"Month the account was created"`
		Routes      []routes.Summary   `json:"routes"`
		Journeys    []journeys.Summary `json:"journeys"`
		community.Relation
		Self bool `json:"self" doc:"This is the viewer's own profile"`
	}
}

// maxProfileRoutes bounds the routes listed on a profile page.
const maxProfileRoutes = 200

func registerDiscover(api huma.API, d Deps) {
	huma.Register(api, huma.Operation{
		OperationID: "discover", Method: http.MethodGet, Path: "/discover",
		Summary:     "Public routes and journeys in a map view",
		Description: "Nearest to the centre of the view first, at most 50.",
		Tags:        []string{"discover"},
	}, func(ctx context.Context, in *discoverInput) (*discoverOutput, error) {
		w, s, e, n, ok := parseBBox(in.BBox)
		if !ok {
			return nil, huma.Error422UnprocessableEntity("bbox must be west,south,east,north with west < east and south < north")
		}
		items, more, err := d.Discover.Search(ctx, discover.Query{
			West: w, South: s, East: e, North: n, Kind: in.Kind, SACMax: in.SACMax,
			MinDurationS: in.DurationMin, MaxDurationS: in.DurationMax,
		})
		if err != nil {
			return nil, err
		}
		out := &discoverOutput{}
		out.Body.Items, out.Body.More = items, more
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-profile", Method: http.MethodGet, Path: "/users/{username}",
		Summary:     "A user's public profile with their public routes and journeys",
		Description: "Only users who published something have a profile.",
		Tags:        []string{"discover"},
	}, func(ctx context.Context, in *profileInput) (*profileOutput, error) {
		notFound := huma.Error404NotFound("no such profile")
		u, err := d.Discover.User(ctx, in.Username)
		if errors.Is(err, discover.ErrNotFound) {
			return nil, notFound
		}
		if err != nil {
			return nil, err
		}
		out := &profileOutput{}
		out.Body.Username, out.Body.DisplayName, out.Body.Since = u.Username, u.DisplayName, u.Since
		if out.Body.Routes, err = d.Routes.ListPublicByOwner(ctx, u.ID, maxProfileRoutes); err != nil {
			return nil, err
		}
		if out.Body.Journeys, err = d.Journeys.ListPublicByOwner(ctx, u.ID); err != nil {
			return nil, err
		}
		if len(out.Body.Routes) == 0 && len(out.Body.Journeys) == 0 {
			return nil, notFound
		}
		v, _, _ := communityViewer(ctx)
		out.Body.Self = v.ID == u.ID
		out.Body.Relation, err = d.Community.Relation(ctx, v.ID, u.ID)
		return out, err
	})
}

func parseBBox(s string) (w, south, e, n float64, ok bool) {
	parts := strings.Split(s, ",")
	if len(parts) != 4 {
		return 0, 0, 0, 0, false
	}
	var v [4]float64
	for i, p := range parts {
		f, err := strconv.ParseFloat(strings.TrimSpace(p), 64)
		if err != nil {
			return 0, 0, 0, 0, false
		}
		v[i] = f
	}
	w, south, e, n = v[0], v[1], v[2], v[3]
	ok = w >= -180 && e <= 180 && south >= -90 && n <= 90 && w < e && south < n
	return w, south, e, n, ok
}
