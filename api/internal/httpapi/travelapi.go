package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/travel"
)

type homesOutput struct {
	Body struct {
		Homes []travel.Home `json:"homes"`
	}
}

type addHomeInput struct {
	Body struct {
		Name    string  `json:"name" minLength:"1" maxLength:"60"`
		Address string  `json:"address" maxLength:"200"`
		Lon     float64 `json:"lon" minimum:"-180" maximum:"180"`
		Lat     float64 `json:"lat" minimum:"-90" maximum:"90"`
	}
}

type homeOutput struct {
	Body travel.Home
}

type homeIDInput struct {
	ID string `path:"id" format:"uuid"`
}

type travelInput struct {
	ID    string `path:"id" format:"uuid"`
	Token string `query:"t" maxLength:"64" doc:"Share token of an unlisted journey or route"`
}

type setTravelInput struct {
	ID    string `path:"id" format:"uuid"`
	Token string `query:"t" maxLength:"64" doc:"Share token of an unlisted journey or route"`
	Body  travel.Travel
}

// Resolve wants a home or a place for each way, and home ids that are ids:
// the database would refuse others.
func (in *setTravelInput) Resolve(huma.Context) []error {
	var errs []error
	for name, w := range map[string]*travel.Way{"body.to": in.Body.To, "body.back": in.Body.Back} {
		if w == nil {
			continue
		}
		switch {
		case (w.HomeID == "") == (w.Place == nil):
			errs = append(errs, &huma.ErrorDetail{Location: name, Message: "either home_id or place"})
		case w.Place != nil && strings.TrimSpace(w.Place.Name) == "":
			errs = append(errs, &huma.ErrorDetail{Location: name + ".place.name", Message: "a place needs a name"})
		case w.HomeID != "":
			if _, err := uuid.Parse(w.HomeID); err != nil {
				errs = append(errs, &huma.ErrorDetail{Location: name + ".home_id", Message: "not an id", Value: w.HomeID})
			}
		}
	}
	return errs
}

type travelOutput struct {
	Body travel.Travel
}

func travelError(err error) error {
	switch {
	case errors.Is(err, travel.ErrNotFound):
		return huma.Error404NotFound("no such home")
	case errors.Is(err, travel.ErrTooMany):
		return huma.Error422UnprocessableEntity("at most 5 homes")
	}
	return err
}

// Homes and the travel to and from journeys and routes are each user's own:
// nobody else sees them, whoever can see the journey or route.
func registerTravel(api huma.API, d Deps) {
	tags := []string{"travel"}

	huma.Register(api, huma.Operation{
		OperationID: "list-homes", Method: http.MethodGet, Path: "/me/homes",
		Summary: "Where one sets off from and returns to by public transport", Tags: tags,
	}, func(ctx context.Context, _ *struct{}) (*homesOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		out := &homesOutput{}
		out.Body.Homes, err = d.Travel.Homes(ctx, u.ID)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "add-home", Method: http.MethodPost, Path: "/me/homes",
		Summary: "Add a home (at most 5)", Tags: tags, DefaultStatus: http.StatusCreated,
	}, func(ctx context.Context, in *addHomeInput) (*homeOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		b := in.Body
		name := strings.TrimSpace(b.Name)
		if name == "" {
			return nil, huma.Error422UnprocessableEntity("a home needs a name")
		}
		h, err := d.Travel.AddHome(ctx, u.ID, travel.Home{Name: name, Address: strings.TrimSpace(b.Address), Lon: b.Lon, Lat: b.Lat})
		if err != nil {
			return nil, travelError(err)
		}
		return &homeOutput{Body: h}, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "delete-home", Method: http.MethodDelete, Path: "/me/homes/{id}",
		Summary: "Remove a home and the travel from and to it", Tags: tags, DefaultStatus: http.StatusNoContent,
	}, func(ctx context.Context, in *homeIDInput) (*struct{}, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		return nil, travelError(d.Travel.DeleteHome(ctx, u.ID, uuid.MustParse(in.ID)))
	})

	// The way to and from what one can see: a journey or a route.
	for _, kind := range []struct {
		name, path, summary string
		of                  travel.For
		load                func(ctx context.Context, id, token string) (string, error)
	}{
		{"journey", "/journeys/{id}/travel", "to the first stage and back from the last", travel.Journey,
			func(ctx context.Context, id, token string) (string, error) {
				j, _, err := loadJourney(ctx, d, id, token)
				return j.ID, err
			}},
		{"route", "/routes/{id}/travel", "to the start and back from the end", travel.Route,
			func(ctx context.Context, id, token string) (string, error) {
				r, _, err := loadRoute(ctx, d, id, token)
				return r.ID, err
			}},
	} {
		huma.Register(api, huma.Operation{
			OperationID: "get-" + kind.name + "-travel", Method: http.MethodGet, Path: kind.path,
			Summary: "One's own way from home or elsewhere " + kind.summary, Tags: tags,
		}, func(ctx context.Context, in *travelInput) (*travelOutput, error) {
			u, err := requireUser(ctx)
			if err != nil {
				return nil, err
			}
			id, err := kind.load(ctx, in.ID, in.Token)
			if err != nil {
				return nil, err
			}
			t, err := d.Travel.Of(ctx, kind.of, u.ID, uuid.MustParse(id))
			return &travelOutput{Body: t}, err
		})

		huma.Register(api, huma.Operation{
			OperationID: "set-" + kind.name + "-travel", Method: http.MethodPut, Path: kind.path,
			Summary:     "Set one's own way there and back",
			Description: "Replaces both directions; one left out is none. Each from or to one of one's homes or a place.",
			Tags:        tags,
		}, func(ctx context.Context, in *setTravelInput) (*travelOutput, error) {
			u, err := requireUser(ctx)
			if err != nil {
				return nil, err
			}
			sid, err := kind.load(ctx, in.ID, in.Token)
			if err != nil {
				return nil, err
			}
			id := uuid.MustParse(sid)
			if err := d.Travel.Set(ctx, kind.of, u.ID, id, in.Body); err != nil {
				return nil, travelError(err)
			}
			t, err := d.Travel.Of(ctx, kind.of, u.ID, id)
			return &travelOutput{Body: t}, err
		})
	}
}
