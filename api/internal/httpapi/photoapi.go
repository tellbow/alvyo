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
	"github.com/tellbow/alvyo/api/internal/community"
	"github.com/tellbow/alvyo/api/internal/photos"
	"github.com/tellbow/alvyo/api/internal/routes"
	"github.com/tellbow/alvyo/swiss/geo"
)

type photosBody struct {
	Photos  []photos.Photo `json:"photos"`
	CanEdit bool           `json:"can_edit" doc:"The viewer may add, change and delete photos"`
}

type photosOutput struct{ Body photosBody }

type photoUploadInput struct {
	ID      string `path:"id" format:"uuid"`
	RawBody huma.MultipartFormFiles[struct {
		File    huma.FormFile `form:"file" required:"true"`
		Caption string        `form:"caption" required:"false" maxLength:"500"`
	}]
}

type photoPatchInput struct {
	ID      string `path:"id" format:"uuid"`
	PhotoID string `path:"photo" format:"uuid"`
	Body    struct {
		Caption *string `json:"caption,omitempty" maxLength:"500"`
		Unpin   bool    `json:"unpin,omitempty" doc:"Remove the photo from the map"`
	}
}

type photoOrderInput struct {
	ID   string `path:"id" format:"uuid"`
	Body struct {
		IDs []string `json:"ids" minItems:"1" maxItems:"100" doc:"Every photo of the item, in the new order"`
	}
}

type photoIDInput struct {
	ID      string `path:"id" format:"uuid"`
	PhotoID string `path:"photo" format:"uuid"`
}

type photoFileInput struct {
	PhotoID string `path:"photo" format:"uuid"`
	Size    string `path:"size" enum:"large,thumb"`
	Token   string `query:"t" doc:"Share token of an unlisted route or journey"`
}

// photoProcessing bounds concurrent image decoding (each takes up to a few
// hundred MB for a large photo).
var photoProcessing = make(chan struct{}, 2)

func photoError(err error) error {
	switch {
	case errors.Is(err, photos.ErrNotFound):
		return huma.Error404NotFound("photo not found")
	case errors.Is(err, photos.ErrLimit):
		return huma.Error422UnprocessableEntity("too many photos: at most 100 per route or journey and 1000 per person")
	case errors.Is(err, photos.ErrOrder):
		return huma.Error422UnprocessableEntity("the order must list every photo once")
	case errors.Is(err, photos.ErrFormat):
		return huma.Error415UnsupportedMediaType("this is not a JPEG, PNG, WebP or HEIC image")
	case errors.Is(err, photos.ErrTooLarge):
		return huma.Error413RequestEntityTooLarge("the image is too large (at most 20 MB and 60 megapixels)")
	}
	return err
}

func registerPhotos(api huma.API, d Deps) {
	for _, it := range socialItems(d) {
		registerPhotoItem(api, d, it)
	}

	huma.Register(api, huma.Operation{
		OperationID: "get-photo", Method: http.MethodGet, Path: "/photos/{photo}/{size}",
		Summary:     "A photo as JPEG, for those who may see its route or journey",
		Description: "Stored without metadata. large: at most 2048 px, thumb: at most 480 px on the long edge.",
		Tags:        []string{"photos"},
	}, func(ctx context.Context, in *photoFileInput) (*imageOutput, error) {
		id, err := uuid.Parse(in.PhotoID)
		if err != nil {
			return nil, photoError(photos.ErrNotFound)
		}
		t, reported, err := d.Photos.Owner(ctx, id)
		if err != nil {
			return nil, photoError(err)
		}
		// Moderators may look at reported photos they could not see otherwise.
		u, _ := auth.UserFrom(ctx)
		if !reported || !isModerator(ctx, u) {
			if _, _, err := socialItemFor(d, t.Kind).load(ctx, t.ID.String(), in.Token); err != nil {
				return nil, photoError(photos.ErrNotFound)
			}
		}
		b, err := d.Photos.Files.Read(id, in.Size)
		if err != nil {
			return nil, photoError(photos.ErrNotFound)
		}
		// Photo files never change; their visibility can, so caches stay private.
		return &imageOutput{ContentType: "image/jpeg", CacheControl: "private, max-age=86400", Body: b}, nil
	})
}

func registerPhotoItem(api huma.API, d Deps, it socialItem) {
	tags := []string{"photos"}
	target := func(t community.Target) photos.Target { return photos.Target{Kind: string(t.Kind), ID: t.ID} }
	// editable loads the item for someone who may edit it. (Moderators
	// remove photos through reports.)
	editable := func(ctx context.Context, rawID string) (photos.Target, error) {
		if _, err := requireUser(ctx); err != nil {
			return photos.Target{}, err
		}
		t, role, err := it.load(ctx, rawID, "")
		if err != nil {
			return photos.Target{}, err
		}
		if role < access.Editor {
			return photos.Target{}, forbidden(access.Editor, it.opName)
		}
		return target(t), nil
	}
	list := func(ctx context.Context, t photos.Target, role access.Role, hidden []geo.Point) (*photosOutput, error) {
		ps, err := d.Photos.List(ctx, t)
		if err != nil {
			return nil, err
		}
		for i, p := range ps {
			for _, h := range hidden {
				if len(p.Pin) == 2 && geo.Distance(h, geo.Point{Lon: p.Pin[0], Lat: p.Pin[1]}) <= routes.PrivacyM {
					ps[i].Pin = nil // in the gallery, not on the map
				}
			}
		}
		return &photosOutput{Body: photosBody{Photos: ps, CanEdit: role >= access.Editor}}, nil
	}
	editorList := func(ctx context.Context, t photos.Target) (*photosOutput, error) {
		return list(ctx, t, access.Editor, nil)
	}

	huma.Register(api, huma.Operation{
		OperationID: "list-" + it.opName + "-photos", Method: http.MethodGet, Path: it.path + "/{id}/photos",
		Summary: "Photos of a " + it.opName + " in gallery order", Tags: tags,
	}, func(ctx context.Context, in *socialInput) (*photosOutput, error) {
		t, role, err := it.load(ctx, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		return list(ctx, target(t), role, t.Hidden)
	})

	huma.Register(api, huma.Operation{
		OperationID: "add-" + it.opName + "-photo", Method: http.MethodPost, Path: it.path + "/{id}/photos",
		Summary:     "Add a photo (owner and editors)",
		Description: "JPEG, PNG, WebP or HEIC up to 20 MB. Metadata is removed; a GPS position within 500 m of the route pins the photo on the map, other positions are dropped.",
		Tags:        tags, MaxBodyBytes: photos.MaxUploadBytes + 1<<20,
	}, func(ctx context.Context, in *photoUploadInput) (*photosOutput, error) {
		t, err := editable(ctx, in.ID)
		if err != nil {
			return nil, err
		}
		u, _ := auth.UserFrom(ctx)
		if !d.Limits.Photo.Allow(u.ID.String()) {
			return nil, errTooMany
		}
		form := in.RawBody.Data()
		select {
		case photoProcessing <- struct{}{}:
		case <-ctx.Done():
			return nil, ctx.Err()
		}
		p, err := photos.Process(form.File)
		<-photoProcessing
		if err != nil {
			return nil, photoError(err)
		}
		if err := d.Photos.Add(ctx, t, u.ID, p, strings.TrimSpace(form.Caption)); err != nil {
			return nil, photoError(err)
		}
		return editorList(ctx, t)
	})

	huma.Register(api, huma.Operation{
		OperationID: "update-" + it.opName + "-photo", Method: http.MethodPatch, Path: it.path + "/{id}/photos/{photo}",
		Summary: "Change a photo's caption or take it off the map (owner and editors)", Tags: tags,
	}, func(ctx context.Context, in *photoPatchInput) (*photosOutput, error) {
		t, err := editable(ctx, in.ID)
		if err != nil {
			return nil, err
		}
		id, err := uuid.Parse(in.PhotoID)
		if err != nil {
			return nil, photoError(photos.ErrNotFound)
		}
		caption := in.Body.Caption
		if caption != nil {
			c := strings.TrimSpace(*caption)
			caption = &c
		}
		if err := d.Photos.Update(ctx, t, id, caption, in.Body.Unpin); err != nil {
			return nil, photoError(err)
		}
		return editorList(ctx, t)
	})

	huma.Register(api, huma.Operation{
		OperationID: "order-" + it.opName + "-photos", Method: http.MethodPut, Path: it.path + "/{id}/photos/order",
		Summary: "Reorder the photos (owner and editors)", Tags: tags,
	}, func(ctx context.Context, in *photoOrderInput) (*photosOutput, error) {
		t, err := editable(ctx, in.ID)
		if err != nil {
			return nil, err
		}
		ids := make([]uuid.UUID, len(in.Body.IDs))
		for i, s := range in.Body.IDs {
			if ids[i], err = uuid.Parse(s); err != nil {
				return nil, photoError(photos.ErrOrder)
			}
		}
		if err := d.Photos.Order(ctx, t, ids); err != nil {
			return nil, photoError(err)
		}
		return editorList(ctx, t)
	})

	huma.Register(api, huma.Operation{
		OperationID: "delete-" + it.opName + "-photo", Method: http.MethodDelete, Path: it.path + "/{id}/photos/{photo}",
		Summary: "Delete a photo (owner and editors)", Tags: tags,
	}, func(ctx context.Context, in *photoIDInput) (*photosOutput, error) {
		t, err := editable(ctx, in.ID)
		if err != nil {
			return nil, err
		}
		id, err := uuid.Parse(in.PhotoID)
		if err != nil {
			return nil, photoError(photos.ErrNotFound)
		}
		if err := d.Photos.Delete(ctx, t, id); err != nil {
			return nil, photoError(err)
		}
		return editorList(ctx, t)
	})
}
