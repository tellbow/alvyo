package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/access"
	"github.com/tellbow/alvyo/api/internal/auth"
	"github.com/tellbow/alvyo/api/internal/grants"
)

type peopleOutput struct {
	Body struct {
		People []grants.Person `json:"people"`
	}
}

type addPersonInput struct {
	ID   string `path:"id" format:"uuid"`
	Body struct {
		Username string   `json:"username,omitempty" maxLength:"31" doc:"An account (either this or email)"`
		Email    string   `json:"email,omitempty" format:"email" maxLength:"254" doc:"An address; it applies once someone signs in with it"`
		Stages   []string `json:"stages,omitempty" maxItems:"200" doc:"The stages they are on; all without"`
	}
}

type personStagesInput struct {
	ID      string `path:"id" format:"uuid"`
	GrantID string `path:"person" format:"uuid"`
	Body    struct {
		Stages []string `json:"stages" maxItems:"200"`
	}
}

type personIDInput struct {
	ID      string `path:"id" format:"uuid"`
	GrantID string `path:"person" format:"uuid"`
}

func stageIDs(raw []string) ([]uuid.UUID, error) {
	if raw == nil {
		return nil, nil
	}
	out := make([]uuid.UUID, 0, len(raw))
	for _, s := range raw {
		id, err := uuid.Parse(s)
		if err != nil {
			return nil, huma.Error422UnprocessableEntity("not a stage: " + s)
		}
		out = append(out, id)
	}
	return out, nil
}

func registerPeople(api huma.API, d Deps) {
	tags := []string{"journeys"}
	// The journey, and whether the caller is its owner; only the owner and
	// those it is shared with see who comes along (not the public).
	load := func(ctx context.Context, rawID string, least access.Role) (grants.Target, access.Role, error) {
		j, role, err := loadJourney(ctx, d, rawID, "")
		if err != nil {
			return grants.Target{}, role, err
		}
		t := grants.Target{Kind: grants.Journey, ID: uuid.MustParse(j.ID), Title: j.Title}
		if role < access.Owner {
			u, ok := auth.UserFrom(ctx)
			shared := access.None
			if ok {
				if shared, err = d.Grants.RoleOf(ctx, grants.Journey, t.ID, u); err != nil {
					return t, role, err
				}
			}
			if shared < access.Viewer {
				return t, role, huma.Error403Forbidden("for the people of this journey")
			}
		}
		if role < least {
			return t, role, forbidden(least, "journey")
		}
		return t, role, nil
	}
	list := func(ctx context.Context, t grants.Target, role access.Role) (*peopleOutput, error) {
		out := &peopleOutput{}
		var err error
		out.Body.People, err = d.Grants.People(ctx, t.ID, role == access.Owner)
		return out, err
	}

	huma.Register(api, huma.Operation{
		OperationID: "list-journey-people", Method: http.MethodGet, Path: "/journeys/{id}/people",
		Summary: "Who comes along, on which stages (owner and people it is shared with)", Tags: tags,
	}, func(ctx context.Context, in *itemInput) (*peopleOutput, error) {
		t, role, err := load(ctx, in.ID, access.Viewer)
		if err != nil {
			return nil, err
		}
		return list(ctx, t, role)
	})

	huma.Register(api, huma.Operation{
		OperationID: "add-journey-person", Method: http.MethodPost, Path: "/journeys/{id}/people",
		Summary:     "Someone comes along (owner)",
		Description: "Someone without access becomes a viewer and is invited by e-mail; a role they have is kept.",
		Tags:        tags,
	}, func(ctx context.Context, in *addPersonInput) (*peopleOutput, error) {
		t, role, err := load(ctx, in.ID, access.Owner)
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
		stages, err := stageIDs(b.Stages)
		if err != nil {
			return nil, err
		}
		if !d.Limits.Invite.Allow(u.ID.String()) {
			return nil, huma.Error429TooManyRequests("too many invitations; try again later")
		}
		err = d.Grants.AddPerson(ctx, t, u, grants.Invite{Username: b.Username, Email: b.Email}, stages)
		switch {
		case errors.Is(err, grants.ErrNoUser):
			return nil, huma.Error422UnprocessableEntity("there is no user with this name")
		case errors.Is(err, grants.ErrSelf):
			return nil, huma.Error422UnprocessableEntity("you are on your journey already")
		case errors.Is(err, grants.ErrTooMany):
			return nil, huma.Error422UnprocessableEntity("too many people have access already")
		case err != nil:
			return nil, err
		}
		return list(ctx, t, role)
	})

	huma.Register(api, huma.Operation{
		OperationID: "set-journey-person-stages", Method: http.MethodPut, Path: "/journeys/{id}/people/{person}",
		Summary: "The stages someone is on (owner and editors)", Tags: tags,
	}, func(ctx context.Context, in *personStagesInput) (*peopleOutput, error) {
		t, role, err := load(ctx, in.ID, access.Editor)
		if err != nil {
			return nil, err
		}
		stages, err := stageIDs(in.Body.Stages)
		if err != nil {
			return nil, err
		}
		if err := d.Grants.SetPersonStages(ctx, t.ID, uuid.MustParse(in.GrantID), stages); err != nil {
			return nil, personError(err)
		}
		return list(ctx, t, role)
	})

	huma.Register(api, huma.Operation{
		OperationID: "remove-journey-person", Method: http.MethodDelete, Path: "/journeys/{id}/people/{person}",
		Summary:     "Someone no longer comes along (owner)",
		Description: "They keep the access they have; stop sharing under grants.",
		Tags:        tags,
	}, func(ctx context.Context, in *personIDInput) (*peopleOutput, error) {
		t, role, err := load(ctx, in.ID, access.Owner)
		if err != nil {
			return nil, err
		}
		if err := d.Grants.RemovePerson(ctx, t.ID, uuid.MustParse(in.GrantID)); err != nil {
			return nil, personError(err)
		}
		return list(ctx, t, role)
	})
}

func personError(err error) error {
	if errors.Is(err, grants.ErrNotFound) {
		return huma.Error404NotFound("not on this journey")
	}
	return err
}
