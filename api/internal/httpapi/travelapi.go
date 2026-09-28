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
	Token string `query:"t" maxLength:"64" doc:"Share token of an unlisted journey"`
}

type setTravelInput struct {
	ID    string `path:"id" format:"uuid"`
	Token string `query:"t" maxLength:"64" doc:"Share token of an unlisted journey"`
	Body  travel.JourneyTravel
}

// Resolve refuses home ids that are not ids: the database would.
func (in *setTravelInput) Resolve(huma.Context) []error {
	var errs []error
	for name, w := range map[string]*travel.Way{"body.to": in.Body.To, "body.back": in.Body.Back} {
		if w == nil {
			continue
		}
		if _, err := uuid.Parse(w.HomeID); err != nil {
			errs = append(errs, &huma.ErrorDetail{Location: name + ".home_id", Message: "not an id", Value: w.HomeID})
		}
	}
	return errs
}

type travelOutput struct {
	Body travel.JourneyTravel
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

// Homes and the travel to and from journeys are each user's own: nobody
// else sees them, whoever can see the journey.
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

	huma.Register(api, huma.Operation{
		OperationID: "get-journey-travel", Method: http.MethodGet, Path: "/journeys/{id}/travel",
		Summary: "One's own way from home to the first stage and back from the last", Tags: tags,
	}, func(ctx context.Context, in *travelInput) (*travelOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		j, _, err := loadJourney(ctx, d, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		t, err := d.Travel.Of(ctx, u.ID, uuid.MustParse(j.ID))
		return &travelOutput{Body: t}, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "set-journey-travel", Method: http.MethodPut, Path: "/journeys/{id}/travel",
		Summary:     "Set one's own way from home and back",
		Description: "Replaces both directions; one left out is none. The homes must be one's own.",
		Tags:        tags,
	}, func(ctx context.Context, in *setTravelInput) (*travelOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		j, _, err := loadJourney(ctx, d, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		id := uuid.MustParse(j.ID)
		if err := d.Travel.Set(ctx, u.ID, id, in.Body); err != nil {
			return nil, travelError(err)
		}
		t, err := d.Travel.Of(ctx, u.ID, id)
		return &travelOutput{Body: t}, err
	})
}
