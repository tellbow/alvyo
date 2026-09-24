package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"log/slog"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/odysgeh/api/internal/access"
	"github.com/tellbow/odysgeh/api/internal/auth"
	"github.com/tellbow/odysgeh/api/internal/imports"
	"github.com/tellbow/odysgeh/api/internal/journeys"
	"github.com/tellbow/odysgeh/api/internal/routes"
	"github.com/tellbow/odysgeh/api/internal/routing"
	"github.com/tellbow/odysgeh/api/internal/stageplan"
	"github.com/tellbow/odysgeh/swiss/geo"
)

// komootSessionTTL bounds how long a Komoot API token is kept (in memory
// only) after logging in, to pick and import tours.
const komootSessionTTL = 30 * time.Minute

type importFileForm struct {
	File  huma.FormFile `form:"file" required:"true"`
	Mode  string        `form:"mode" required:"false" enum:"route,routes,journey" doc:"Several tracks: one route, one route each, or a journey with a stage each"`
	Title string        `form:"title" required:"false" maxLength:"120" doc:"Title of the route or journey; the track name otherwise"`
}

type stageImportInput struct {
	ID      string `path:"id" format:"uuid"`
	StageID string `path:"stage" format:"uuid"`
	RawBody huma.MultipartFormFiles[struct {
		File    huma.FormFile `form:"file" required:"true"`
		Replace bool          `form:"replace" required:"false" doc:"Replace the stage's route if it has one (409 otherwise)"`
	}]
}

type importPreviewInput struct {
	RawBody huma.MultipartFormFiles[struct {
		File huma.FormFile `form:"file" required:"true"`
	}]
}

type trackSummary struct {
	Name      string  `json:"name"`
	Points    int     `json:"points"`
	DistanceM float64 `json:"distance_m"`
	Inside    bool    `json:"inside" doc:"Entirely within Switzerland and Liechtenstein (else it cannot be imported)"`
	Nights    int     `json:"nights" doc:"Pauses of 5 hours or more in a recording: it can become a stage per day"`
}

type stagesImportInput struct {
	RawBody huma.MultipartFormFiles[struct {
		File        huma.FormFile `form:"file" required:"true"`
		Days        int           `form:"days" required:"false" minimum:"0" maximum:"60" doc:"Number of stages; with neither this nor hours_per_day, a recording is split at its nights"`
		HoursPerDay float64       `form:"hours_per_day" required:"false" minimum:"0" maximum:"16" doc:"Hiking time per stage (Swiss hiking time)"`
		MaxHours    float64       `form:"max_hours" required:"false" minimum:"0" maximum:"20"`
		Ends        string        `form:"ends" required:"false" doc:"Comma-separated place ids to end the stages at (from a proposal's earlier and later)"`
	}]
}

type stagesImportOutput struct {
	Body struct {
		stageplan.Proposal
		Title string `json:"title" doc:"The track's name, for the journey"`
	}
}

type importPreviewOutput struct {
	Body struct {
		Format string         `json:"format" enum:"gpx,kml,tcx,fit"`
		Tracks []trackSummary `json:"tracks"`
	}
}

type importInput struct {
	RawBody huma.MultipartFormFiles[importFileForm]
}

type importedRoute struct {
	ID    string `json:"id" format:"uuid"`
	Title string `json:"title"`
	Ref   string `json:"ref,omitempty" doc:"The Komoot tour id"`
}

type importOutput struct {
	Body struct {
		Routes    []importedRoute   `json:"routes"`
		JourneyID string            `json:"journey_id,omitempty" format:"uuid"`
		Skipped   []imports.Skipped `json:"skipped"`
	}
}

type komootLoginInput struct {
	Body struct {
		Email    string `json:"email" maxLength:"254"`
		Password string `json:"password" maxLength:"200"`
	}
}

type komootTour struct {
	imports.KomootTour
	ImportedRouteID string `json:"imported_route_id,omitempty" format:"uuid"`
}

type komootToursOutput struct {
	Body struct {
		Session    string       `json:"session" doc:"Pass to the other Komoot calls; expires after 30 minutes"`
		Tours      []komootTour `json:"tours"`
		TotalPages int          `json:"total_pages"`
	}
}

type komootToursInput struct {
	Session string `query:"session" required:"true"`
	Page    int    `query:"page" minimum:"0"`
}

type komootImportInput struct {
	Body struct {
		Session string  `json:"session"`
		TourIDs []int64 `json:"tour_ids" minItems:"1" maxItems:"10" doc:"At most 10 per request; the page imports in batches"`
	}
}

// komootSessions holds Komoot API tokens briefly, bound to our user.
type komootSessions struct {
	mu sync.Mutex
	m  map[string]komootSessionEntry
}

type komootSessionEntry struct {
	owner   uuid.UUID
	session imports.KomootSession
	until   time.Time
}

func (s *komootSessions) put(owner uuid.UUID, ks imports.KomootSession) string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	id := base64.RawURLEncoding.EncodeToString(b)
	now := time.Now()
	s.mu.Lock()
	defer s.mu.Unlock()
	for k, e := range s.m {
		if now.After(e.until) {
			delete(s.m, k)
		}
	}
	s.m[id] = komootSessionEntry{owner: owner, session: ks, until: now.Add(komootSessionTTL)}
	return id
}

func (s *komootSessions) get(owner uuid.UUID, id string) (imports.KomootSession, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, ok := s.m[id]
	if !ok || e.owner != owner || time.Now().After(e.until) {
		return imports.KomootSession{}, false
	}
	return e.session, true
}

func registerImports(api huma.API, d Deps) {
	tags := []string{"imports"}
	sessions := &komootSessions{m: map[string]komootSessionEntry{}}

	parse := func(f huma.FormFile) (string, []imports.Track, error) {
		format, tracks, err := imports.Parse(f.Filename, f)
		switch {
		case errors.Is(err, imports.ErrFormat):
			return "", nil, huma.Error422UnprocessableEntity("this is not a GPX, KML, TCX or FIT file")
		case err != nil:
			return "", nil, huma.Error422UnprocessableEntity("the file could not be read: " + err.Error())
		case len(tracks) == 0:
			return "", nil, huma.Error422UnprocessableEntity("the file contains no track")
		}
		return format, tracks, nil
	}

	huma.Register(api, huma.Operation{
		OperationID: "preview-import", Method: http.MethodPost, Path: "/imports/preview",
		Summary: "The tracks in a GPX, KML, TCX or FIT file", Tags: tags,
		MaxBodyBytes: imports.MaxFileBytes + 1<<20,
	}, func(ctx context.Context, in *importPreviewInput) (*importPreviewOutput, error) {
		if _, err := requireUser(ctx); err != nil {
			return nil, err
		}
		format, tracks, err := parse(in.RawBody.Data().File)
		if err != nil {
			return nil, err
		}
		out := &importPreviewOutput{}
		out.Body.Format = format
		for _, t := range tracks {
			out.Body.Tracks = append(out.Body.Tracks, trackSummary{
				Name: t.Name, Points: len(t.Points),
				DistanceM: float64(int(geo.CumulativeDistance(t.Points)[len(t.Points)-1])),
				Inside:    inside(t.Points),
				Nights:    len(imports.Nights(t)) - 1,
			})
		}
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "import-file", Method: http.MethodPost, Path: "/imports",
		Summary:     "Import the tracks of a file as private routes or a journey",
		Description: "Tracks outside Switzerland and Liechtenstein are skipped and reported.",
		Tags:        tags, MaxBodyBytes: imports.MaxFileBytes + 1<<20,
	}, func(ctx context.Context, in *importInput) (*importOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		form := in.RawBody.Data()
		format, tracks, err := parse(form.File)
		if err != nil {
			return nil, err
		}
		// Each track is matched and its elevations sampled: they count.
		if !d.Limits.Import.AllowN(u.ID.String(), len(tracks)) {
			return nil, huma.Error429TooManyRequests("too many imports; try again in a few minutes")
		}
		out := &importOutput{}
		out.Body.Routes, out.Body.Skipped = []importedRoute{}, []imports.Skipped{}
		name := form.Title
		if name == "" {
			name = tracks[0].Name
		}
		switch {
		case form.Mode == "journey" && len(tracks) > 1:
			j, skipped, err := d.Importer.Journey(ctx, u.ID, name, tracks)
			if err != nil {
				return nil, err
			}
			out.Body.JourneyID = j.ID
			out.Body.Skipped = append(out.Body.Skipped, skipped...)
			return out, nil
		case form.Mode == "routes":
			// one route per track, below
		default:
			if len(tracks) > 1 {
				tracks = []imports.Track{imports.Join(name, tracks)}
			}
			if form.Title != "" {
				tracks[0].Name = form.Title
			}
		}
		for _, t := range tracks {
			r, err := d.Importer.Route(ctx, u.ID, t, imports.Source{Kind: format})
			if err != nil {
				if imports.Reason(err) == "other" {
					slog.ErrorContext(ctx, "import", "err", err)
				}
				out.Body.Skipped = append(out.Body.Skipped, imports.Skipped{Name: t.Name, Reason: imports.Reason(err)})
				continue
			}
			out.Body.Routes = append(out.Body.Routes, importedRoute{ID: r.ID, Title: r.Title})
		}
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "import-stages", Method: http.MethodPost, Path: "/imports/stages",
		Summary: "Propose the stages of a long track: at the nights of a recording, or by days or hours",
		Description: "The tracks of the file are joined. Nothing is saved: POST /journeys with the stages does. " +
			"Split by days or hours, the stages end at huts, hotels, campsites or stops near the track.",
		Tags: tags, MaxBodyBytes: imports.MaxFileBytes + 1<<20,
	}, func(ctx context.Context, in *stagesImportInput) (*stagesImportOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		form := in.RawBody.Data()
		_, tracks, err := parse(form.File)
		if err != nil {
			return nil, err
		}
		track := tracks[0]
		if len(tracks) > 1 {
			track = imports.Join(track.Name, tracks)
		}
		planner := &stageplan.Planner{Router: d.Importer.Router, DB: d.DB}
		content := func(t imports.Track) (routes.Content, error) {
			c, err := d.Importer.Content(ctx, t)
			if err != nil && imports.Reason(err) != "other" {
				return c, huma.Error422UnprocessableEntity(err.Error())
			}
			return c, err
		}
		var proposal stageplan.Proposal
		if form.Days == 0 && form.HoursPerDay == 0 {
			nights := imports.Nights(track)
			if len(nights) < 2 {
				return nil, huma.Error422UnprocessableEntity("the track has no nights: give days or hours_per_day")
			}
			if !d.Limits.Import.AllowN(u.ID.String(), len(nights)) {
				return nil, huma.Error429TooManyRequests("too many imports; try again in a few minutes")
			}
			var days [][]routing.Leg
			profile := "hike"
			for _, t := range nights {
				c, err := content(t)
				if err != nil {
					return nil, err
				}
				days = append(days, c.Legs)
				if c.Profile == "alpine" {
					profile = "alpine"
				}
			}
			proposal, err = planner.ByDay(ctx, days, profile)
		} else {
			if !d.Limits.Import.Allow(u.ID.String()) {
				return nil, huma.Error429TooManyRequests("too many imports; try again in a few minutes")
			}
			var c routes.Content
			if c, err = content(track); err != nil {
				return nil, err
			}
			var ends []string
			for id := range strings.SplitSeq(form.Ends, ",") {
				if id = strings.TrimSpace(id); id != "" {
					ends = append(ends, id)
				}
			}
			proposal, err = planner.Split(ctx, c.Legs, stageplan.Request{
				Profile: c.Profile, Ends: ends,
				Days: stageplan.Days{N: form.Days, TargetS: form.HoursPerDay * 3600, MaxS: form.MaxHours * 3600},
			})
		}
		switch {
		case errors.Is(err, stageplan.ErrUnknownEnd):
			return nil, huma.Error422UnprocessableEntity(err.Error())
		case err != nil:
			return nil, err
		}
		out := &stagesImportOutput{}
		out.Body.Proposal, out.Body.Title = proposal, track.Name
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "import-stage-route", Method: http.MethodPost, Path: "/journeys/{id}/stages/{stage}/import",
		Summary:     "Import a GPX, KML, TCX or FIT file as a stage's route",
		Description: "Several tracks in the file are joined into one route.",
		Tags:        []string{"journeys"}, MaxBodyBytes: imports.MaxFileBytes + 1<<20,
	}, func(ctx context.Context, in *stageImportInput) (*journeyOutput, error) {
		j, role, err := journeyAs(ctx, d, in.ID, access.Editor)
		if err != nil {
			return nil, err
		}
		u, _ := auth.UserFrom(ctx)
		form := in.RawBody.Data()
		idx := slices.IndexFunc(j.StageList, func(st journeys.Stage) bool { return st.ID == in.StageID })
		if idx < 0 {
			return nil, huma.Error404NotFound("stage not found")
		}
		st := j.StageList[idx]
		if st.Route != nil && !form.Replace {
			return nil, journeyError(journeys.ErrHasRoute)
		}
		_, tracks, err := parse(form.File)
		if err != nil {
			return nil, err
		}
		if !d.Limits.Import.AllowN(u.ID.String(), len(tracks)) {
			return nil, huma.Error429TooManyRequests("too many imports; try again in a few minutes")
		}
		c, err := d.Importer.Content(ctx, imports.Join(tracks[0].Name, tracks))
		if err != nil {
			if imports.Reason(err) == "other" {
				return nil, err
			}
			return nil, huma.Error422UnprocessableEntity(err.Error())
		}
		if st.Route == nil {
			// The journey owner owns stage routes, whoever imports them.
			_, err = d.Journeys.SetStageRoute(ctx, uuid.MustParse(j.ID), uuid.MustParse(st.ID),
				uuid.MustParse(j.OwnerID), stageTitle(j, idx), c)
			return mutateJourney(ctx, d.Journeys, j, role, err)
		}
		r, err := d.Routes.Get(ctx, uuid.MustParse(st.Route.ID))
		if err != nil {
			return nil, routeError(err)
		}
		if _, err := d.Routes.Update(ctx, uuid.MustParse(r.ID), r.Version, r.Meta, &c); err != nil {
			return nil, routeError(err)
		}
		return mutateJourney(ctx, d.Journeys, j, role, nil)
	})

	// Komoot's tours, with those imported before marked.
	listTours := func(ctx context.Context, owner uuid.UUID, ks imports.KomootSession, page int) ([]komootTour, int, error) {
		tours, pages, err := d.Komoot.Tours(ctx, ks, page, 100)
		if err != nil {
			return nil, 0, komootError(err)
		}
		done, err := d.Routes.ImportedRefs(ctx, owner, "komoot")
		if err != nil {
			return nil, 0, err
		}
		out := make([]komootTour, len(tours))
		for i, t := range tours {
			out[i] = komootTour{KomootTour: t, ImportedRouteID: done[strconv.FormatInt(t.ID, 10)]}
		}
		return out, pages, nil
	}

	huma.Register(api, huma.Operation{
		OperationID: "komoot-login", Method: http.MethodPost, Path: "/imports/komoot/login",
		Summary:     "Log in to Komoot and list the tours",
		Description: "The password goes to Komoot only and is not stored; Komoot's session token is kept in memory for 30 minutes.",
		Tags:        tags,
	}, func(ctx context.Context, in *komootLoginInput) (*komootToursOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if !d.Limits.KomootLogin.Allow(u.ID.String()) {
			return nil, huma.Error429TooManyRequests("too many Komoot logins; try again later")
		}
		ks, err := d.Komoot.Login(ctx, in.Body.Email, in.Body.Password)
		if err != nil {
			return nil, komootError(err)
		}
		out := &komootToursOutput{}
		if out.Body.Tours, out.Body.TotalPages, err = listTours(ctx, u.ID, ks, 0); err != nil {
			return nil, err
		}
		out.Body.Session = sessions.put(u.ID, ks)
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "komoot-tours", Method: http.MethodGet, Path: "/imports/komoot/tours",
		Summary: "Another page of Komoot tours", Tags: tags,
	}, func(ctx context.Context, in *komootToursInput) (*komootToursOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		ks, ok := sessions.get(u.ID, in.Session)
		if !ok {
			return nil, huma.Error401Unauthorized("the Komoot session expired; log in again")
		}
		out := &komootToursOutput{}
		out.Body.Session = in.Session
		out.Body.Tours, out.Body.TotalPages, err = listTours(ctx, u.ID, ks, in.Page)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "komoot-import", Method: http.MethodPost, Path: "/imports/komoot",
		Summary: "Import Komoot tours as private routes", Tags: tags,
	}, func(ctx context.Context, in *komootImportInput) (*importOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		ks, ok := sessions.get(u.ID, in.Body.Session)
		if !ok {
			return nil, huma.Error401Unauthorized("the Komoot session expired; log in again")
		}
		if !d.Limits.Import.Allow(u.ID.String()) {
			return nil, huma.Error429TooManyRequests("too many imports; try again in a few minutes")
		}
		done, err := d.Routes.ImportedRefs(ctx, u.ID, "komoot")
		if err != nil {
			return nil, err
		}
		out := &importOutput{}
		out.Body.Routes, out.Body.Skipped = []importedRoute{}, []imports.Skipped{}
		for _, id := range in.Body.TourIDs {
			ref := strconv.FormatInt(id, 10)
			if done[ref] != "" {
				out.Body.Skipped = append(out.Body.Skipped, imports.Skipped{Name: ref, Reason: "duplicate"})
				continue
			}
			t, err := d.Komoot.Track(ctx, ks, id)
			if err != nil {
				out.Body.Skipped = append(out.Body.Skipped, imports.Skipped{Name: ref, Reason: "other"})
				continue
			}
			r, err := d.Importer.Route(ctx, u.ID, t, imports.Source{Kind: "komoot", Ref: ref})
			if err != nil {
				out.Body.Skipped = append(out.Body.Skipped, imports.Skipped{Name: t.Name, Reason: imports.Reason(err)})
				continue
			}
			out.Body.Routes = append(out.Body.Routes, importedRoute{ID: r.ID, Title: r.Title, Ref: ref})
		}
		return out, nil
	})
}

func komootError(err error) error {
	switch {
	case errors.Is(err, imports.ErrKomootLogin):
		return huma.Error422UnprocessableEntity("Komoot did not accept the e-mail address or password")
	case errors.Is(err, imports.ErrKomoot):
		return huma.Error502BadGateway("Komoot did not answer as expected")
	}
	return err
}

func inside(pts []geo.Point) bool {
	for _, p := range pts {
		if p.Lon < 5.9 || p.Lon > 10.6 || p.Lat < 45.8 || p.Lat > 47.9 {
			return false
		}
	}
	return true
}
