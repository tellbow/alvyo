package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/danielgtaylor/huma/v2"

	"github.com/tellbow/alvyo/api/internal/community"
	"github.com/tellbow/alvyo/api/internal/dbq"
	"github.com/tellbow/alvyo/api/internal/discover"
)

type userSearchInput struct {
	Q string `query:"q" maxLength:"60" doc:"Start of a username or part of a name; without it, who published lately"`
}

func (in *userSearchInput) Resolve(huma.Context) []error {
	if q := strings.TrimSpace(in.Q); q != "" && len([]rune(q)) < 2 {
		return []error{&huma.ErrorDetail{Location: "query.q", Message: "at least 2 characters", Value: in.Q}}
	}
	return nil
}

type userSearchOutput struct {
	Body struct {
		Users []community.FriendRef `json:"users"`
	}
}

type friendListsOutput struct{ Body community.FriendLists }

type friendLinkOutput struct {
	Body struct {
		Token string `json:"token" doc:"For the invite link /friends/invite/{token}"`
	}
}

type friendInviteInput struct {
	Token string `path:"token" maxLength:"64"`
}

type inviterOutput struct{ Body community.UserRef }

// registerFriends: friends both ways, found by the search among public
// profiles, or through someone's invite link.
func registerFriends(api huma.API, d Deps) {
	tags := []string{"community"}

	huma.Register(api, huma.Operation{
		OperationID: "search-users", Method: http.MethodGet, Path: "/users",
		Summary: "Find public profiles by username or name, or browse those who published lately; at most 30", Tags: tags,
	}, func(ctx context.Context, in *userSearchInput) (*userSearchOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if !d.Limits.Search.Allow(u.ID.String()) {
			return nil, huma.Error429TooManyRequests("too many searches")
		}
		out := &userSearchOutput{}
		out.Body.Users, err = d.Community.SearchUsers(ctx, u.ID, in.Q)
		return out, err
	})

	// Asking needs a profile one may see: a public one, or one whose owner
	// asked first (a private profile is reached through its invite link).
	friendOp := func(id, method, summary string, do func(ctx context.Context, u dbq.User, o discover.User) error) {
		huma.Register(api, huma.Operation{
			OperationID: id, Method: method, Path: "/users/{username}/friend", Summary: summary, Tags: tags,
		}, func(ctx context.Context, in *usernameInput) (*relationOutput, error) {
			u, err := requireUser(ctx)
			if err != nil {
				return nil, err
			}
			o, err := d.Discover.User(ctx, in.Username)
			if errors.Is(err, discover.ErrNotFound) {
				return nil, huma.Error404NotFound("no such user")
			}
			if err != nil {
				return nil, err
			}
			if o.ID == u.ID {
				return nil, huma.Error422UnprocessableEntity("that is you")
			}
			if err := do(ctx, u, o); err != nil {
				return nil, err
			}
			r, err := d.Community.Relation(ctx, u.ID, o.ID)
			return &relationOutput{Body: r}, err
		})
	}
	friendOp("request-friend", http.MethodPut, "Ask a user to be friends, or accept their request",
		func(ctx context.Context, u dbq.User, o discover.User) error {
			state, err := d.Community.FriendState(ctx, u.ID, o.ID)
			if err != nil {
				return err
			}
			if !o.Public && state == community.NoFriend {
				return huma.Error404NotFound("no such user")
			}
			if !d.Limits.Invite.Allow(u.ID.String()) { // asking sends an e-mail
				return huma.Error429TooManyRequests("too many requests")
			}
			return communityError(d.Community.RequestFriend(ctx, u, o.ID))
		})
	friendOp("remove-friend", http.MethodDelete, "End a friendship, or withdraw or decline a request",
		func(ctx context.Context, u dbq.User, o discover.User) error {
			return d.Community.Unfriend(ctx, u.ID, o.ID)
		})

	huma.Register(api, huma.Operation{
		OperationID: "list-friends", Method: http.MethodGet, Path: "/me/friends",
		Summary: "My friends and the open friend requests", Tags: tags,
	}, func(ctx context.Context, _ *struct{}) (*friendListsOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		l, err := d.Community.FriendLists(ctx, u.ID)
		return &friendListsOutput{Body: l}, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "list-friend-suggestions", Method: http.MethodGet, Path: "/me/friend-suggestions",
		Summary: "People the user might know: friends of friends with a public profile, at most 10", Tags: tags,
	}, func(ctx context.Context, _ *struct{}) (*userSearchOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		out := &userSearchOutput{}
		out.Body.Users, err = d.Community.Suggestions(ctx, u.ID)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "dismiss-friend-suggestion", Method: http.MethodDelete, Path: "/me/friend-suggestions/{username}",
		Summary: "Do not suggest this user again", Tags: tags, DefaultStatus: http.StatusNoContent,
	}, func(ctx context.Context, in *usernameInput) (*struct{}, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		o, err := d.Discover.User(ctx, in.Username)
		if errors.Is(err, discover.ErrNotFound) || err == nil && !o.Public {
			return nil, huma.Error404NotFound("no such user")
		}
		if err != nil {
			return nil, err
		}
		return nil, d.Community.Dismiss(ctx, u.ID, o.ID)
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-friend-link", Method: http.MethodGet, Path: "/me/friend-link",
		Summary: "My invite link: whoever opens it becomes my friend", Tags: tags,
	}, func(ctx context.Context, _ *struct{}) (*friendLinkOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		out := &friendLinkOutput{}
		out.Body.Token, err = d.Community.FriendToken(ctx, u.ID)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "rotate-friend-link", Method: http.MethodPost, Path: "/me/friend-link",
		Summary: "A new invite link; the old one stops working", Tags: tags,
	}, func(ctx context.Context, _ *struct{}) (*friendLinkOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		out := &friendLinkOutput{}
		out.Body.Token, err = d.Community.RotateFriendToken(ctx, u.ID)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-friend-invite", Method: http.MethodGet, Path: "/friend-invites/{token}",
		Summary: "Whose invite link this is", Tags: tags,
	}, func(ctx context.Context, in *friendInviteInput) (*inviterOutput, error) {
		_, ref, err := d.Community.Inviter(ctx, in.Token)
		if err != nil {
			return nil, communityError(err)
		}
		return &inviterOutput{Body: ref}, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "accept-friend-invite", Method: http.MethodPost, Path: "/friend-invites/{token}",
		Summary: "Become friends with the owner of the invite link", Tags: tags,
	}, func(ctx context.Context, in *friendInviteInput) (*inviterOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		ref, err := d.Community.AcceptInvite(ctx, u.ID, in.Token)
		if err != nil {
			return nil, communityError(err)
		}
		return &inviterOutput{Body: ref}, nil
	})
}
