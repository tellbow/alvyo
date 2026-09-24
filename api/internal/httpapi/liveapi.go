package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/odysgeh/api/internal/dbq"
	"github.com/tellbow/odysgeh/api/internal/live"
)

type contactsOutput struct {
	Body struct {
		Contacts []live.Contact `json:"contacts"`
	}
}

type contactOutput struct {
	Body live.Contact
}

type addContactInput struct {
	Body struct {
		Name  string `json:"name" minLength:"1" maxLength:"80"`
		Email string `json:"email" format:"email" maxLength:"254"`
	}
}

type contactIDInput struct {
	ID string `path:"id" format:"uuid"`
}

type startLiveInput struct {
	Body struct {
		RouteID     string    `json:"route_id,omitempty" format:"uuid" doc:"The route hiked, to show it"`
		Title       string    `json:"title" minLength:"1" maxLength:"120"`
		ContactIDs  []string  `json:"contact_ids" minItems:"1" maxItems:"10"`
		ExpectedEnd time.Time `json:"expected_end" doc:"The contacts are alerted 30 minutes after it"`
	}
}

type liveOutput struct {
	Body live.Share
}

type liveIDInput struct {
	ID string `path:"id" format:"uuid"`
}

type livePositionsInput struct {
	ID   string `path:"id" format:"uuid"`
	Body struct {
		Points []live.Fix `json:"points" minItems:"1" maxItems:"2000"`
	}
}

type extendLiveInput struct {
	ID   string `path:"id" format:"uuid"`
	Body struct {
		ExpectedEnd time.Time `json:"expected_end"`
	}
}

type liveTokenInput struct {
	Token string `path:"token" maxLength:"64"`
}

type liveViewOutput struct {
	Body live.View
}

func liveError(err error) error {
	switch {
	case err == nil:
		return nil
	case errors.Is(err, live.ErrNotFound):
		return huma.Error404NotFound("not found")
	case errors.Is(err, live.ErrDuplicate):
		return huma.Error409Conflict("this address is a contact already")
	case errors.Is(err, live.ErrTooMany):
		return huma.Error422UnprocessableEntity("at most 10 contacts")
	case errors.Is(err, live.ErrNoRecipients):
		return huma.Error422UnprocessableEntity("choose at least one of your contacts")
	case errors.Is(err, live.ErrBadEnd):
		return huma.Error422UnprocessableEntity(err.Error())
	case errors.Is(err, live.ErrEnded):
		return huma.Error409Conflict("the hike has ended")
	}
	return err
}

func hiker(u dbq.User) live.Hiker {
	return live.Hiker{ID: u.ID, DisplayName: u.DisplayName, Email: u.Email, Locale: u.Locale}
}

func registerLive(api huma.API, d Deps) {
	tags := []string{"live"}
	store := d.Live

	huma.Register(api, huma.Operation{
		OperationID: "list-contacts", Method: http.MethodGet, Path: "/me/contacts",
		Summary: "The people one shares hikes with", Tags: tags,
	}, func(ctx context.Context, _ *struct{}) (*contactsOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		out := &contactsOutput{}
		out.Body.Contacts, err = store.Contacts(ctx, u.ID)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "add-contact", Method: http.MethodPost, Path: "/me/contacts",
		Summary: "Add a contact (at most 10)", Tags: tags, DefaultStatus: http.StatusCreated,
	}, func(ctx context.Context, in *addContactInput) (*contactOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		c, err := store.AddContact(ctx, u.ID, strings.TrimSpace(in.Body.Name), strings.TrimSpace(in.Body.Email))
		if err != nil {
			return nil, liveError(err)
		}
		return &contactOutput{Body: c}, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "delete-contact", Method: http.MethodDelete, Path: "/me/contacts/{id}",
		Summary: "Remove a contact", Tags: tags, DefaultStatus: http.StatusNoContent,
	}, func(ctx context.Context, in *contactIDInput) (*struct{}, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		return nil, liveError(store.DeleteContact(ctx, u.ID, uuid.MustParse(in.ID)))
	})

	huma.Register(api, huma.Operation{
		OperationID: "start-live", Method: http.MethodPost, Path: "/live",
		Summary:     "Share a hike's position with some contacts",
		Description: "They get the link by e-mail, and an e-mail with the last position if the hike has not ended 30 minutes after the expected end. A share still running ends.",
		Tags:        tags, DefaultStatus: http.StatusCreated,
	}, func(ctx context.Context, in *startLiveInput) (*liveOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if u.EmailVerifiedAt == nil {
			return nil, huma.Error403Forbidden("confirm your e-mail address first")
		}
		if !d.Limits.Invite.Allow(u.ID.String()) {
			return nil, errTooMany
		}
		st := live.Start{Title: strings.TrimSpace(in.Body.Title), ExpectedEnd: in.Body.ExpectedEnd, RouteID: optionalID(in.Body.RouteID)}
		for _, raw := range in.Body.ContactIDs {
			if id, err := uuid.Parse(raw); err == nil {
				st.ContactIDs = append(st.ContactIDs, id)
			}
		}
		if st.RouteID != nil {
			// Only a route the hiker may see is shown to the contacts.
			if _, _, err := loadRoute(ctx, d, st.RouteID.String(), ""); err != nil {
				return nil, err
			}
		}
		sh, err := store.Start(ctx, hiker(u), st)
		if err != nil {
			return nil, liveError(err)
		}
		return &liveOutput{Body: sh}, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "live-positions", Method: http.MethodPost, Path: "/live/{id}/positions",
		Summary: "Positions of a shared hike (also those recorded while offline)", Tags: tags,
		DefaultStatus: http.StatusNoContent,
	}, func(ctx context.Context, in *livePositionsInput) (*struct{}, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		return nil, liveError(store.AddPositions(ctx, u.ID, uuid.MustParse(in.ID), in.Body.Points))
	})

	huma.Register(api, huma.Operation{
		OperationID: "extend-live", Method: http.MethodPatch, Path: "/live/{id}",
		Summary: "Move the expected end («später»)", Tags: tags, DefaultStatus: http.StatusNoContent,
	}, func(ctx context.Context, in *extendLiveInput) (*struct{}, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		return nil, liveError(store.Extend(ctx, hiker(u), uuid.MustParse(in.ID), in.Body.ExpectedEnd))
	})

	huma.Register(api, huma.Operation{
		OperationID: "end-live", Method: http.MethodPost, Path: "/live/{id}/end",
		Summary: "End the sharing", Tags: tags, DefaultStatus: http.StatusNoContent,
	}, func(ctx context.Context, in *liveIDInput) (*struct{}, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		return nil, liveError(store.End(ctx, hiker(u), uuid.MustParse(in.ID)))
	})

	huma.Register(api, huma.Operation{
		OperationID: "live-view", Method: http.MethodGet, Path: "/live/view/{token}",
		Summary:     "A shared hike, for those with the link",
		Description: "No login: the link is the key. Works until 24 hours after the end.",
		Tags:        tags,
	}, func(ctx context.Context, in *liveTokenInput) (*liveViewOutput, error) {
		v, err := store.Public(ctx, in.Token)
		if err != nil {
			return nil, liveError(err)
		}
		return &liveViewOutput{Body: v}, nil
	})
}
