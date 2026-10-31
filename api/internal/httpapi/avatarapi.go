package httpapi

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/dbq"
	"github.com/tellbow/alvyo/api/internal/photos"
)

type avatarUploadInput struct {
	RawBody huma.MultipartFormFiles[struct {
		File huma.FormFile `form:"file" required:"true"`
	}]
}

type avatarFileInput struct {
	ID string `path:"avatar" format:"uuid"`
}

func registerAvatars(api huma.API, d Deps) {
	tags := []string{"me"}
	// set stores the new picture's id; the trigger puts the old one in the trash.
	set := func(ctx context.Context, user, avatar *uuid.UUID) (*meOutput, error) {
		if _, err := d.DB.Exec(ctx, `UPDATE users SET avatar = $2 WHERE id = $1`, *user, avatar); err != nil {
			return nil, err
		}
		u, err := dbq.New(d.DB).GetUserByID(ctx, *user)
		if err != nil {
			return nil, err
		}
		return fullMe(ctx, d, u)
	}

	huma.Register(api, huma.Operation{
		OperationID: "set-avatar", Method: http.MethodPut, Path: "/me/avatar",
		Summary:     "Set the profile picture",
		Description: "JPEG, PNG, WebP or HEIC up to 20 MB, cropped to a square from its middle, without metadata.",
		Tags:        tags, MaxBodyBytes: photos.MaxUploadBytes + 1<<20,
	}, func(ctx context.Context, in *avatarUploadInput) (*meOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if !d.Limits.Photo.Allow(u.ID.String()) {
			return nil, errTooMany
		}
		select {
		case photoProcessing <- struct{}{}:
		case <-ctx.Done():
			return nil, ctx.Err()
		}
		b, err := photos.Avatar(in.RawBody.Data().File)
		<-photoProcessing
		if err != nil {
			return nil, photoError(err)
		}
		id := uuid.New()
		if err := d.Photos.Files.WriteAvatar(id, b); err != nil {
			return nil, err
		}
		return set(ctx, &u.ID, &id)
	})

	huma.Register(api, huma.Operation{
		OperationID: "delete-avatar", Method: http.MethodDelete, Path: "/me/avatar",
		Summary: "Remove the profile picture", Tags: tags,
	}, func(ctx context.Context, _ *struct{}) (*meOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		return set(ctx, &u.ID, nil)
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-avatar", Method: http.MethodGet, Path: "/avatars/{avatar}",
		Summary:     "A profile picture as JPEG (256 px square)",
		Description: "The id is random and given only where the person shows; a new picture gets a new id.",
		Tags:        tags,
	}, func(_ context.Context, in *avatarFileInput) (*imageOutput, error) {
		id, err := uuid.Parse(in.ID)
		if err != nil {
			return nil, photoError(photos.ErrNotFound)
		}
		b, err := d.Photos.Files.Read(id, photos.AvatarSize)
		if err != nil {
			return nil, photoError(photos.ErrNotFound)
		}
		return &imageOutput{ContentType: "image/jpeg", CacheControl: "public, max-age=31536000, immutable", Body: b}, nil
	})
}
