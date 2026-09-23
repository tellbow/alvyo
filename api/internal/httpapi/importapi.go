package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/odysgeh/api/internal/imports"
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
		if !d.Limits.Import.Allow(u.ID.String()) {
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
