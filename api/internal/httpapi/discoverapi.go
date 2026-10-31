package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/collections"
	"github.com/tellbow/alvyo/api/internal/community"
	"github.com/tellbow/alvyo/api/internal/discover"
	"github.com/tellbow/alvyo/api/internal/done"
	"github.com/tellbow/alvyo/api/internal/grants"
	"github.com/tellbow/alvyo/api/internal/journeys"
	"github.com/tellbow/alvyo/api/internal/og"
	"github.com/tellbow/alvyo/api/internal/routes"
)

type discoverInput struct {
	BBox        string `query:"bbox" required:"true" doc:"The map view: west,south,east,north (WGS84)" example:"7.9,46.55,8.1,46.7"`
	Kind        string `query:"kind" enum:"route,journey" doc:"Only routes or only journeys"`
	SACMax      int    `query:"sac_max" minimum:"0" maximum:"6" doc:"Hardest SAC grade allowed; 0 for any"`
	DurationMin int    `query:"duration_min" minimum:"0" doc:"Minimum hiking time (s); for journeys of the longest stage"`
	DurationMax int    `query:"duration_max" minimum:"0" doc:"Maximum hiking time (s); for journeys of the longest stage"`
	Official    string `query:"official" enum:"only,none" doc:"only: the official Wanderland routes; none: those of people; both if left out"`
}

type discoverOutput struct {
	Body struct {
		Items []discover.Item `json:"items"`
		More  bool            `json:"more" doc:"There are more results than shown: zoom in or narrow the filters"`
	}
}

type myMapInput struct {
	BBox         string   `query:"bbox" required:"true" doc:"The map view: west,south,east,north (WGS84)" example:"7.9,46.55,8.1,46.7"`
	Kind         []string `query:"kind,explode" enum:"route,journey,hike" doc:"Only these kinds (hike: recorded with the app); all if none"`
	Tags         []string `query:"tags,explode" maxItems:"20" doc:"Items with any of these tags (without case); all if none"`
	Shared       bool     `query:"shared" doc:"Also the routes and journeys others shared with me"`
	DistanceMin  float64  `query:"distance_min" minimum:"0" doc:"Metres; 0 for no bound"`
	DistanceMax  float64  `query:"distance_max" minimum:"0" doc:"Metres; 0 for no bound"`
	DurationMin  int      `query:"duration_min" minimum:"0" doc:"Hiking time (s); 0 for no bound"`
	DurationMax  int      `query:"duration_max" minimum:"0" doc:"Hiking time (s); 0 for no bound"`
	SACMin       int      `query:"sac_min" minimum:"0" maximum:"6" doc:"Hardest SAC grade at least; 0 for no bound"`
	SACMax       int      `query:"sac_max" minimum:"0" maximum:"6" doc:"Hardest SAC grade at most; 0 for no bound"`
	LongestStage bool     `query:"longest_stage" doc:"Journeys: the distance and time bounds apply to the longest stage, not the whole journey"`
	Done         string   `query:"done" enum:"done,planned" doc:"done: only what I hiked; planned: only what I have not; all if left out"`
}

type myMapOutput struct {
	Body struct {
		Items []discover.MineItem `json:"items"`
		More  bool                `json:"more" doc:"There are more results than shown: zoom in or narrow the filters"`
	}
}

type profileInput struct {
	Username string `path:"username"`
}

type profileOutput struct {
	Body struct {
		Username    string                    `json:"username"`
		DisplayName string                    `json:"display_name"`
		Avatar      string                    `json:"avatar,omitempty" format:"uuid" doc:"Profile picture: GET /avatars/{avatar}"`
		Since       time.Time                 `json:"since" doc:"Month the account was created"`
		Routes      []routes.Summary          `json:"routes" doc:"The user's routes the viewer may open and, for friends, others' routes the user hiked; done_on is when the user hiked it, for friends only"`
		Journeys    []journeys.Summary        `json:"journeys" doc:"As routes"`
		Collections []collections.Summary     `json:"collections" doc:"The user's collections the viewer may open"`
		Outlines    map[string][][][2]float64 `json:"outlines" doc:"The (lon, lat) lines of each route and journey listed by its id, simplified for a thumbnail"`
		community.Relation
		Self bool `json:"self" doc:"This is the viewer's own profile"`
	}
}

type sitemapOutput struct {
	Body struct {
		Entries []discover.SitemapEntry `json:"entries"`
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
			MinDurationS: in.DurationMin, MaxDurationS: in.DurationMax, Official: in.Official,
		})
		if err != nil {
			return nil, err
		}
		out := &discoverOutput{}
		out.Body.Items, out.Body.More = items, more
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "my-map", Method: http.MethodGet, Path: "/me/map",
		Summary:     "The logged-in user's routes, journeys and recorded hikes in a map view",
		Description: "Nearest to the centre of the view first, at most 200.",
		Tags:        []string{"discover"},
	}, func(ctx context.Context, in *myMapInput) (*myMapOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		w, s, e, n, ok := parseBBox(in.BBox)
		if !ok {
			return nil, huma.Error422UnprocessableEntity("bbox must be west,south,east,north with west < east and south < north")
		}
		id, email := grants.Grantee(u)
		items, more, err := d.Discover.Mine(ctx, discover.MineQuery{
			UserID: id, VerifiedEmail: email, West: w, South: s, East: e, North: n,
			Kinds: in.Kind, Tags: in.Tags, Shared: in.Shared,
			MinDistanceM: in.DistanceMin, MaxDistanceM: in.DistanceMax,
			MinDurationS: in.DurationMin, MaxDurationS: in.DurationMax,
			MinSAC: in.SACMin, MaxSAC: in.SACMax, LongestStage: in.LongestStage, Done: in.Done,
		})
		if err != nil {
			return nil, err
		}
		out := &myMapOutput{}
		out.Body.Items, out.Body.More = items, more
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "sitemap", Method: http.MethodGet, Path: "/sitemap",
		Summary:     "Public routes, journeys, collections and profiles, for the sitemap",
		Description: "The most recently changed first, at most 12500.",
		Tags:        []string{"discover"},
	}, func(ctx context.Context, _ *struct{}) (*sitemapOutput, error) {
		out := &sitemapOutput{}
		var err error
		out.Body.Entries, err = d.Discover.Sitemap(ctx)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-profile", Method: http.MethodGet, Path: "/users/{username}",
		Summary:     "A user's profile with the routes, journeys and collections the viewer may see",
		Description: "A public profile is shown to signed-in users, and to everyone once it has published something; a private one to friends and to those it asked to be friends. The user sees it always.",
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
		out.Body.Username, out.Body.DisplayName, out.Body.Avatar, out.Body.Since = u.Username, u.DisplayName, u.Avatar, u.Since
		v, viewer, signedIn := communityViewer(ctx)
		out.Body.Self = v.ID == u.ID
		if out.Body.Relation, err = d.Community.Relation(ctx, v.ID, u.ID); err != nil {
			return nil, err
		}
		// Hikes, as in the news: for friends, unless switched off (feedback
		// issue 58). Only what the viewer may open is listed.
		hikes := out.Body.Self || out.Body.Friend == community.Friends && u.ShareHikes
		vid, email := grants.Grantee(viewer)
		if out.Body.Routes, err = d.Routes.ListForProfile(ctx, u.ID, vid, email, hikes, maxProfileRoutes); err != nil {
			return nil, err
		}
		if out.Body.Journeys, err = d.Journeys.ListForProfile(ctx, u.ID, vid, email, hikes); err != nil {
			return nil, err
		}
		if out.Body.Collections, err = d.Collections.ListForProfile(ctx, u.ID, collections.Viewer{UserID: vid, VerifiedEmail: email}); err != nil {
			return nil, err
		}
		rs, js := out.Body.Routes, out.Body.Journeys
		if hikes {
			if err := doneDays(ctx, d, u.ID, done.Route, len(rs), func(i int) string { return rs[i].ID },
				func(i int, on *string) { rs[i].DoneOn = on }); err != nil {
				return nil, err
			}
			if err := doneDays(ctx, d, u.ID, done.Journey, len(js), func(i int) string { return js[i].ID },
				func(i int, on *string) { js[i].DoneOn = on }); err != nil {
				return nil, err
			}
		}
		var routeIDs, journeyIDs []uuid.UUID
		for _, r := range rs {
			routeIDs = append(routeIDs, uuid.MustParse(r.ID))
		}
		for _, j := range js {
			journeyIDs = append(journeyIDs, uuid.MustParse(j.ID))
		}
		if out.Body.Outlines, err = d.Discover.ProfileOutlines(ctx, routeIDs, journeyIDs); err != nil {
			return nil, err
		}
		// A private profile is for friends and for whom it asks to be one; a
		// public one for the signed-in (the search finds it), and for all once
		// it has something to show. One's own always.
		friend := out.Body.Self || out.Body.Friend == community.Friends || out.Body.Friend == community.Incoming
		if !friend && (!u.Public || !signedIn && len(out.Body.Routes) == 0 && len(out.Body.Journeys) == 0) {
			return nil, notFound
		}
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-profile-image", Method: http.MethodGet, Path: "/users/{username}/og.png",
		Summary:     "Preview image of a public profile for link previews (1200×630)",
		Description: "The lines of the user's public routes and journeys; 404 for a profile that is not public or has none.",
		Tags:        []string{"discover"},
	}, func(ctx context.Context, in *profileInput) (*imageOutput, error) {
		u, err := d.Discover.User(ctx, in.Username)
		if errors.Is(err, discover.ErrNotFound) || err == nil && !u.Public {
			return nil, huma.Error404NotFound("no such profile")
		}
		if err != nil {
			return nil, err
		}
		card := og.Card{Title: u.DisplayName, Stats: "@" + u.Username}
		if card.Lines, err = d.Discover.ProfileLines(ctx, u.ID); err != nil {
			return nil, err
		}
		if len(card.Lines) == 0 {
			return nil, huma.Error404NotFound("no public route or journey")
		}
		card.Credit = officialCredit(u.Username)
		b, err := d.Images.PNG(imageKey(u.ID.String(), card), card)
		if err != nil {
			return nil, err
		}
		return &imageOutput{ContentType: "image/png", CacheControl: "public, max-age=3600", Body: b}, nil
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
