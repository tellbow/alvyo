package auth

import (
	"context"

	"github.com/tellbow/odysgeh/api/internal/dbq"
)

type userKey struct{}

// WithUser returns a context carrying the authenticated user.
func WithUser(ctx context.Context, u dbq.User) context.Context {
	return context.WithValue(ctx, userKey{}, u)
}

// UserFrom returns the authenticated user, if any.
func UserFrom(ctx context.Context) (dbq.User, bool) {
	u, ok := ctx.Value(userKey{}).(dbq.User)
	return u, ok
}
