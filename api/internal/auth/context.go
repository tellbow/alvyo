package auth

import (
	"context"

	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/dbq"
)

type (
	userKey        struct{}
	accessTokenKey struct{}
)

// WithUser returns a context carrying the authenticated user.
func WithUser(ctx context.Context, u dbq.User) context.Context {
	return context.WithValue(ctx, userKey{}, u)
}

// UserFrom returns the authenticated user, if any.
func UserFrom(ctx context.Context) (dbq.User, bool) {
	u, ok := ctx.Value(userKey{}).(dbq.User)
	return u, ok
}

// WithAccessToken marks the context's user as authenticated by the personal
// access token id, which may only read.
func WithAccessToken(ctx context.Context, id uuid.UUID) context.Context {
	return context.WithValue(ctx, accessTokenKey{}, id)
}

// AccessTokenFrom returns the access token the user came with, if any.
func AccessTokenFrom(ctx context.Context) (uuid.UUID, bool) {
	id, ok := ctx.Value(accessTokenKey{}).(uuid.UUID)
	return id, ok
}
