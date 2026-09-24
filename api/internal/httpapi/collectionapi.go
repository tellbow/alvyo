package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/odysgeh/api/internal/access"
	"github.com/tellbow/odysgeh/api/internal/auth"
	"github.com/tellbow/odysgeh/api/internal/collections"
	"github.com/tellbow/odysgeh/api/internal/grants"
	"github.com/tellbow/odysgeh/api/internal/og"
)

type collectionBody struct {
	collections.Collection
	Role       string `json:"role" enum:"owner,editor,viewer"`
	CanEdit    bool   `json:"can_edit"`
	ShareToken string `json:"share_token,omitempty" doc:"Owner only; the link is /collections/{id}?t=token"`
}

type collectionOutput struct {
	ETag string `header:"ETag"`
	Body collectionBody
}

type collectionIDInput struct {
	ID    string `path:"id" format:"uuid"`
	Token string `query:"t" doc:"Share token of an unlisted collection"`
}

type createCollectionInput struct {
	Body struct {
		Title       string   `json:"title" minLength:"1" maxLength:"120"`
		Description string   `json:"description,omitempty" maxLength:"5000"`
		Visibility  string   `json:"visibility,omitempty" enum:"private,unlisted,public" default:"private"`
		Tags        []string `json:"tags,omitempty" maxItems:"20" doc:"At most 20, each up to 40 characters; repeats (ignoring case) are dropped"`
	}
}

type updateCollectionInput struct {
	ID      string `path:"id" format:"uuid"`
	IfMatch string `header:"If-Match" required:"true"`
	Body    struct {
		Title       *string  `json:"title,omitempty" minLength:"1" maxLength:"120"`
		Description *string  `json:"description,omitempty" maxLength:"5000"`
		Visibility  *string  `json:"visibility,omitempty" enum:"private,unlisted,public"`
		Tags        []string `json:"tags,omitempty" maxItems:"20" doc:"Replaces the tags; [] removes them"`
	}
}

type addItemInput struct {
	ID   string `path:"id" format:"uuid"`
	Body struct {
		RouteID   string `json:"route_id,omitempty" format:"uuid" doc:"Either this or journey_id"`
		JourneyID string `json:"journey_id,omitempty" format:"uuid"`
		Note      string `json:"note,omitempty" maxLength:"1000"`
	}
}

type updateItemInput struct {
	ID     string `path:"id" format:"uuid"`
	ItemID string `path:"item" format:"uuid"`
	Body   struct {
		Note     *string `json:"note,omitempty" maxLength:"1000"`
		Position *int    `json:"position,omitempty" minimum:"0" doc:"0-based; the others shift"`
	}
}

type itemIDInput struct {
	ID     string `path:"id" format:"uuid"`
	ItemID string `path:"item" format:"uuid"`
}

type collectionListOutput struct {
	Body struct {
		Collections []collections.Summary `json:"collections"`
	}
}

// viewer is the caller as a collection reader.
func viewer(ctx context.Context) collections.Viewer {
	u, ok := auth.UserFrom(ctx)
	if !ok {
		return collections.Viewer{}
	}
	id, email := grants.Grantee(u)
	return collections.Viewer{UserID: id, VerifiedEmail: email}
}

// loadCollection returns a collection the caller may see (with the items
// they may see) and their role; others get 404.
func loadCollection(ctx context.Context, d Deps, rawID, token string) (collections.Collection, access.Role, error) {
	id, err := uuid.Parse(rawID)
	if err != nil {
		return collections.Collection{}, access.None, huma.Error404NotFound("collection not found")
	}
	res, err := d.Collections.Access(ctx, id)
	if err != nil {
		return collections.Collection{}, access.None, collectionError(err)
	}
	role, err := d.roleOn(ctx, res, grants.Collection, id, token)
	if err != nil {
		return collections.Collection{}, access.None, err
	}
	if role == access.None {
		return collections.Collection{}, access.None, huma.Error404NotFound("collection not found")
	}
	c, err := d.Collections.Get(ctx, id, viewer(ctx))
	return c, role, collectionError(err)
}

func collectionAs(ctx context.Context, d Deps, rawID string, need access.Role) (collections.Collection, access.Role, error) {
	c, role, err := loadCollection(ctx, d, rawID, "")
	if err != nil {
		return c, role, err
	}
	if role < need {
		return c, role, forbidden(need, "collection")
	}
	return c, role, nil
}

func collectionResponse(c collections.Collection, role access.Role) *collectionOutput {
	body := collectionBody{Collection: c, Role: role.String(), CanEdit: role >= access.Editor}
	if role == access.Owner && c.Visibility == "unlisted" {
		body.ShareToken = c.ShareToken
	}
	return &collectionOutput{ETag: strconv.Quote(strconv.Itoa(c.Version)), Body: body}
}

// reloadCollection answers a change with the collection as it is now.
func reloadCollection(ctx context.Context, d Deps, c collections.Collection, role access.Role, err error) (*collectionOutput, error) {
	if err != nil {
		return nil, collectionError(err)
	}
	updated, err := d.Collections.Get(ctx, uuid.MustParse(c.ID), viewer(ctx))
	if err != nil {
		return nil, collectionError(err)
	}
	return collectionResponse(updated, role), nil
}

func collectionError(err error) error {
	switch {
	case err == nil:
		return nil
	case errors.Is(err, collections.ErrNotFound):
		return huma.Error404NotFound("collection not found")
	case errors.Is(err, collections.ErrItemNotFound):
		return huma.Error404NotFound("item not found")
	case errors.Is(err, collections.ErrVersion):
		return huma.Error412PreconditionFailed("the collection was changed in the meantime; reload it")
	case errors.Is(err, collections.ErrDuplicate):
		return huma.Error409Conflict("already in the collection")
	case errors.Is(err, collections.ErrFull):
		return huma.Error422UnprocessableEntity(err.Error())
	}
	return err
}

func registerCollections(api huma.API, d Deps) {
	tags := []string{"collections"}
	store := d.Collections

	huma.Register(api, huma.Operation{
		OperationID: "create-collection", Method: http.MethodPost, Path: "/collections",
		Summary: "Start a collection of routes and journeys", Tags: tags, DefaultStatus: http.StatusCreated,
	}, func(ctx context.Context, in *createCollectionInput) (*collectionOutput, error) {
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
		id, err := store.Create(ctx, u.ID, collections.Meta{
			Title: strings.TrimSpace(in.Body.Title), Description: in.Body.Description, Visibility: in.Body.Visibility,
			Tags: labels,
		})
		if err != nil {
			return nil, err
		}
		c, err := store.Get(ctx, id, viewer(ctx))
		if err != nil {
			return nil, err
		}
		return collectionResponse(c, access.Owner), nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "list-my-collections", Method: http.MethodGet, Path: "/collections",
		Summary: "The logged-in user's collections", Tags: tags,
	}, func(ctx context.Context, _ *struct{}) (*collectionListOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		list, err := store.ListByOwner(ctx, u.ID)
		if err != nil {
			return nil, err
		}
		out := &collectionListOutput{}
		out.Body.Collections = list
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-collection", Method: http.MethodGet, Path: "/collections/{id}",
		Summary:     "A collection with the items the caller may see",
		Description: "A collection never grants access: items the caller may not open are left out.",
		Tags:        tags,
	}, func(ctx context.Context, in *collectionIDInput) (*collectionOutput, error) {
		c, role, err := loadCollection(ctx, d, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		return collectionResponse(c, role), nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-collection-image", Method: http.MethodGet, Path: "/collections/{id}/og.png",
		Summary:     "Preview image of a collection for link previews (1200×630)",
		Description: "The items the caller may see; 404 while none has a line.",
		Tags:        tags,
	}, func(ctx context.Context, in *collectionIDInput) (*imageOutput, error) {
		c, _, err := loadCollection(ctx, d, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		card := og.Card{Title: c.Title, Stats: "@" + c.OwnerUsername}
		for _, it := range c.ItemList {
			card.Lines = append(card.Lines, it.Lines...)
		}
		if len(card.Lines) == 0 {
			return nil, huma.Error404NotFound("no item has a line")
		}
		b, err := d.Images.PNG(imageKey(c.ID, card), card)
		if err != nil {
			return nil, err
		}
		// Which items show depends on the caller: never in shared caches.
		return &imageOutput{ContentType: "image/png", CacheControl: "private, max-age=3600", Body: b}, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "update-collection", Method: http.MethodPatch, Path: "/collections/{id}",
		Summary: "Change a collection's title, description or visibility", Tags: tags,
	}, func(ctx context.Context, in *updateCollectionInput) (*collectionOutput, error) {
		c, role, err := collectionAs(ctx, d, in.ID, access.Editor)
		if err != nil {
			return nil, err
		}
		version, err := strconv.Atoi(strings.Trim(strings.TrimPrefix(in.IfMatch, "W/"), `"`))
		if err != nil {
			return nil, huma.Error400BadRequest("If-Match must be the collection version")
		}
		m := c.Meta
		if in.Body.Title != nil {
			m.Title = strings.TrimSpace(*in.Body.Title)
		}
		if in.Body.Description != nil {
			m.Description = *in.Body.Description
		}
		if in.Body.Tags != nil {
			if m.Tags, err = normalizeTags(in.Body.Tags); err != nil {
				return nil, err
			}
		}
		if in.Body.Visibility != nil && *in.Body.Visibility != c.Visibility {
			if role < access.Owner {
				return nil, forbidden(access.Owner, "collection")
			}
			u, _ := auth.UserFrom(ctx)
			if err := checkPublish(u, *in.Body.Visibility); err != nil {
				return nil, err
			}
			m.Visibility = *in.Body.Visibility
		}
		return reloadCollection(ctx, d, c, role, store.UpdateMeta(ctx, uuid.MustParse(c.ID), version, m))
	})

	huma.Register(api, huma.Operation{
		OperationID: "delete-collection", Method: http.MethodDelete, Path: "/collections/{id}",
		Summary: "Delete a collection (its routes and journeys stay)", Tags: tags, DefaultStatus: http.StatusNoContent,
	}, func(ctx context.Context, in *collectionIDInput) (*struct{}, error) {
		c, _, err := collectionAs(ctx, d, in.ID, access.Owner)
		if err != nil {
			return nil, err
		}
		return nil, collectionError(store.Delete(ctx, uuid.MustParse(c.ID)))
	})

	huma.Register(api, huma.Operation{
		OperationID: "rotate-collection-link", Method: http.MethodPost, Path: "/collections/{id}/link/rotate",
		Summary: "Replace the share link; the old link stops working", Tags: tags,
	}, func(ctx context.Context, in *collectionIDInput) (*shareTokenOutput, error) {
		c, _, err := collectionAs(ctx, d, in.ID, access.Owner)
		if err != nil {
			return nil, err
		}
		token, err := store.RotateShareToken(ctx, uuid.MustParse(c.ID))
		if err != nil {
			return nil, err
		}
		out := &shareTokenOutput{}
		out.Body.ShareToken = token
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "add-collection-item", Method: http.MethodPost, Path: "/collections/{id}/items",
		Summary:     "Add a route or journey you can open",
		Description: "Stage routes are added through their journey.",
		Tags:        tags,
	}, func(ctx context.Context, in *addItemInput) (*collectionOutput, error) {
		c, role, err := collectionAs(ctx, d, in.ID, access.Editor)
		if err != nil {
			return nil, err
		}
		b := in.Body
		kind, target := "", b.RouteID
		switch {
		case b.RouteID != "" && b.JourneyID == "":
			r, _, err := loadRoute(ctx, d, b.RouteID, "")
			if err != nil {
				return nil, err
			}
			if r.JourneyID != "" {
				return nil, huma.Error422UnprocessableEntity("add the journey instead of one of its stages")
			}
			kind = "route"
		case b.JourneyID != "" && b.RouteID == "":
			if _, _, err := loadJourney(ctx, d, b.JourneyID, ""); err != nil {
				return nil, err
			}
			kind, target = "journey", b.JourneyID
		default:
			return nil, huma.Error422UnprocessableEntity("give either route_id or journey_id")
		}
		u, _ := auth.UserFrom(ctx)
		return reloadCollection(ctx, d, c, role,
			store.AddItem(ctx, uuid.MustParse(c.ID), kind, uuid.MustParse(target), b.Note, u.ID))
	})

	huma.Register(api, huma.Operation{
		OperationID: "update-collection-item", Method: http.MethodPatch, Path: "/collections/{id}/items/{item}",
		Summary: "Change an item's note or move it", Tags: tags,
	}, func(ctx context.Context, in *updateItemInput) (*collectionOutput, error) {
		c, role, err := collectionAs(ctx, d, in.ID, access.Editor)
		if err != nil {
			return nil, err
		}
		return reloadCollection(ctx, d, c, role, store.UpdateItem(ctx, uuid.MustParse(c.ID), uuid.MustParse(in.ItemID),
			collections.ItemPatch{Note: in.Body.Note, Position: in.Body.Position}))
	})

	huma.Register(api, huma.Operation{
		OperationID: "delete-collection-item", Method: http.MethodDelete, Path: "/collections/{id}/items/{item}",
		Summary: "Remove an item (the route or journey stays)", Tags: tags,
	}, func(ctx context.Context, in *itemIDInput) (*collectionOutput, error) {
		c, role, err := collectionAs(ctx, d, in.ID, access.Editor)
		if err != nil {
			return nil, err
		}
		return reloadCollection(ctx, d, c, role, store.DeleteItem(ctx, uuid.MustParse(c.ID), uuid.MustParse(in.ItemID)))
	})
}
