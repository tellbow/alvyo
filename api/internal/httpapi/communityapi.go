package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/access"
	"github.com/tellbow/alvyo/api/internal/auth"
	"github.com/tellbow/alvyo/api/internal/community"
	"github.com/tellbow/alvyo/api/internal/dbq"
	"github.com/tellbow/alvyo/api/internal/discover"
)

type socialBody struct {
	community.Social
	CanComment  bool `json:"can_comment" doc:"The viewer may write a comment"`
	CanModerate bool `json:"can_moderate" doc:"The viewer owns the item or moderates: may switch comments off and delete any"`
}

type socialOutput struct{ Body socialBody }

type socialInput struct {
	ID    string `path:"id" format:"uuid"`
	Token string `query:"t" doc:"Share token of an unlisted item"`
}

type commentInput struct {
	ID    string `path:"id" format:"uuid"`
	Token string `query:"t"`
	Body  struct {
		Body     string `json:"body" minLength:"1" maxLength:"2000"`
		ParentID string `json:"parent_id,omitempty" format:"uuid" doc:"Reply to this comment"`
	}
}

type editCommentInput struct {
	ID        string `path:"id" format:"uuid"`
	CommentID string `path:"comment" format:"uuid"`
	Token     string `query:"t"`
	Body      struct {
		Body string `json:"body" minLength:"1" maxLength:"2000"`
	}
}

type commentIDInput struct {
	ID        string `path:"id" format:"uuid"`
	CommentID string `path:"comment" format:"uuid"`
	Token     string `query:"t"`
}

type socialSettingsInput struct {
	ID   string `path:"id" format:"uuid"`
	Body struct {
		CommentsEnabled bool `json:"comments_enabled"`
	}
}

type usernameInput struct {
	Username string `path:"username"`
}

type relationOutput struct{ Body community.Relation }

type blockedOutput struct {
	Body struct {
		Users []community.UserRef `json:"users"`
	}
}

type feedInput struct {
	Before time.Time `query:"before" doc:"Continue after this published_at (from the previous page)"`
}

type feedOutput struct {
	Body struct {
		Items []community.FeedItem `json:"items"`
		Next  *time.Time           `json:"next,omitempty" doc:"Pass as before to get older items"`
	}
}

type reportInput struct {
	Body struct {
		Kind     string `json:"kind" enum:"route,journey,comment,user,photo"`
		ID       string `json:"id,omitempty" format:"uuid" doc:"The route, journey, comment or photo"`
		Username string `json:"username,omitempty" maxLength:"31" doc:"The user"`
		Token    string `json:"token,omitempty" doc:"Share token of an unlisted route or journey"`
		Reason   string `json:"reason" enum:"spam,offensive,dangerous,other"`
		Note     string `json:"note,omitempty" maxLength:"1000"`
	}
}

type reportsOutput struct {
	Body struct {
		Reports []community.Report `json:"reports"`
	}
}

type resolveInput struct {
	ID   string `path:"id" format:"uuid"`
	Body struct {
		Resolution string `json:"resolution" enum:"dismissed,removed" doc:"removed deletes a comment or photo, makes a route or journey private or bans a user"`
	}
}

type settingsInput struct {
	Body struct {
		NotifyComments *bool    `json:"notify_comments,omitempty" doc:"E-mail on comments on my routes and journeys"`
		NotifyFollows  *bool    `json:"notify_follows,omitempty" doc:"E-mail when someone follows me or asks to be friends"`
		ProfilePublic  *bool    `json:"profile_public,omitempty" doc:"Found by the user search; else seen by friends only"`
		Locale         *string  `json:"locale,omitempty" enum:"de,en,fr,it" doc:"Language of e-mails"`
		SpeedFactor    *float64 `json:"speed_factor,omitempty" minimum:"0.3" maximum:"3" doc:"Pace: hiking times as a multiple of the signposts' (1.2: a fifth slower)"`
	}
}

// feedPage is how many items a feed page has.
const feedPage = 30

// socialItem is a kind of item that has likes and comments.
type socialItem struct {
	path   string // "/routes" or "/journeys"
	opName string // "route" or "journey"
	load   func(ctx context.Context, rawID, token string) (community.Target, access.Role, error)
}

func isModerator(u dbq.User) bool { return u.Role == "moderator" || u.Role == "admin" }

// communityViewer is the logged-in caller, or the anonymous viewer.
func communityViewer(ctx context.Context) (community.Viewer, dbq.User, bool) {
	u, ok := auth.UserFrom(ctx)
	if !ok {
		return community.Viewer{}, u, false
	}
	return community.Viewer{ID: u.ID, Moderator: isModerator(u)}, u, true
}

func communityError(err error) error {
	switch {
	case errors.Is(err, community.ErrNotFound):
		return huma.Error404NotFound("not found")
	case errors.Is(err, community.ErrForbidden):
		return huma.Error403Forbidden("not allowed")
	case errors.Is(err, community.ErrCommentsOff):
		return huma.Error403Forbidden("comments are switched off here")
	case errors.Is(err, community.ErrBlocked):
		return huma.Error403Forbidden("the owner blocked you")
	case errors.Is(err, community.ErrStaff):
		return huma.Error422UnprocessableEntity("moderators and admins are not banned from a report")
	}
	return err
}

// socialItems are routes and journeys, loaded for the caller (404 if they
// may not see them).
func socialItems(d Deps) []socialItem {
	return []socialItem{
		{path: "/routes", opName: "route",
			load: func(ctx context.Context, rawID, token string) (community.Target, access.Role, error) {
				r, role, err := loadRoute(ctx, d, rawID, token)
				if err != nil {
					return community.Target{}, role, err
				}
				if r.JourneyID != "" {
					return community.Target{}, role, huma.Error422UnprocessableEntity("comments on a stage belong to its journey")
				}
				return community.Target{Kind: community.Route, ID: uuid.MustParse(r.ID), OwnerID: uuid.MustParse(r.OwnerID),
					Title: r.Title, Hidden: r.Hidden}, role, nil
			}},
		{path: "/journeys", opName: "journey",
			load: func(ctx context.Context, rawID, token string) (community.Target, access.Role, error) {
				j, role, err := loadJourney(ctx, d, rawID, token)
				if err != nil {
					return community.Target{}, role, err
				}
				return community.Target{Kind: community.Journey, ID: uuid.MustParse(j.ID), OwnerID: uuid.MustParse(j.OwnerID), Title: j.Title}, role, nil
			}},
	}
}

// socialItemFor returns the socialItem of kind ("route" or "journey").
func socialItemFor(d Deps, kind string) socialItem {
	if kind == "journey" {
		return socialItems(d)[1]
	}
	return socialItems(d)[0]
}

func registerCommunity(api huma.API, d Deps) {
	items := socialItems(d)
	for _, it := range items {
		registerSocialItem(api, d, it)
	}
	registerFollows(api, d)
	registerFriends(api, d)
	registerReports(api, d)

	huma.Register(api, huma.Operation{
		OperationID: "update-me", Method: http.MethodPatch, Path: "/me",
		Summary: "Change settings: notification e-mails, their language, the pace and the profile's visibility", Tags: []string{"me"},
	}, func(ctx context.Context, in *settingsInput) (*meOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		b := in.Body
		if err := d.Community.SetSettings(ctx, u.ID, community.Settings{
			NotifyComments: b.NotifyComments, NotifyFollows: b.NotifyFollows, ProfilePublic: b.ProfilePublic,
			Locale: b.Locale, Pace: b.SpeedFactor,
		}); err != nil {
			return nil, err
		}
		if u, err = dbq.New(d.DB).GetUserByID(ctx, u.ID); err != nil {
			return nil, err
		}
		return fullMe(ctx, d, u)
	})
}

func registerSocialItem(api huma.API, d Deps, it socialItem) {
	tags := []string{"community"}
	social := func(ctx context.Context, t community.Target) (*socialOutput, error) {
		v, u, loggedIn := communityViewer(ctx)
		sc, err := d.Community.Social(ctx, t, v)
		if err != nil {
			return nil, communityError(err)
		}
		out := &socialOutput{Body: socialBody{Social: sc}}
		out.Body.CanComment = loggedIn && u.EmailVerifiedAt != nil && sc.CommentsEnabled && !sc.BlockedByOwner
		out.Body.CanModerate = loggedIn && (t.OwnerID == u.ID || v.Moderator)
		if !sc.CommentsEnabled && !out.Body.CanModerate {
			out.Body.Comments = []community.Comment{} // hidden while switched off
		}
		return out, nil
	}

	huma.Register(api, huma.Operation{
		OperationID: "get-" + it.opName + "-social", Method: http.MethodGet, Path: it.path + "/{id}/social",
		Summary: "Likes and comments of a " + it.opName, Tags: tags,
	}, func(ctx context.Context, in *socialInput) (*socialOutput, error) {
		t, _, err := it.load(ctx, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		return social(ctx, t)
	})

	huma.Register(api, huma.Operation{
		OperationID: "like-" + it.opName, Method: http.MethodPut, Path: it.path + "/{id}/like",
		Summary: "Like a " + it.opName, Tags: tags,
	}, func(ctx context.Context, in *socialInput) (*socialOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		t, _, err := it.load(ctx, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		if err := d.Community.Like(ctx, t, u.ID); err != nil {
			return nil, err
		}
		return social(ctx, t)
	})

	huma.Register(api, huma.Operation{
		OperationID: "unlike-" + it.opName, Method: http.MethodDelete, Path: it.path + "/{id}/like",
		Summary: "Take back the like of a " + it.opName, Tags: tags,
	}, func(ctx context.Context, in *socialInput) (*socialOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		t, _, err := it.load(ctx, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		if err := d.Community.Unlike(ctx, t, u.ID); err != nil {
			return nil, err
		}
		return social(ctx, t)
	})

	huma.Register(api, huma.Operation{
		OperationID: "comment-" + it.opName, Method: http.MethodPost, Path: it.path + "/{id}/comments",
		Summary:     "Comment on a " + it.opName,
		Description: "Needs a verified e-mail address. The owner gets an e-mail (at most one per 15 minutes and item).",
		Tags:        tags,
	}, func(ctx context.Context, in *commentInput) (*socialOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if u.EmailVerifiedAt == nil {
			return nil, huma.Error403Forbidden("confirm your e-mail address first")
		}
		if strings.TrimSpace(in.Body.Body) == "" {
			return nil, huma.Error422UnprocessableEntity("the comment is empty")
		}
		t, _, err := it.load(ctx, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		if !d.Limits.Comment.Allow(u.ID.String()) {
			return nil, errTooMany
		}
		if err := d.Community.AddComment(ctx, t, u, in.Body.Body, optionalID(in.Body.ParentID)); err != nil {
			return nil, communityError(err)
		}
		return social(ctx, t)
	})

	huma.Register(api, huma.Operation{
		OperationID: "edit-" + it.opName + "-comment", Method: http.MethodPatch, Path: it.path + "/{id}/comments/{comment}",
		Summary: "Change the text of one's own comment", Tags: tags,
	}, func(ctx context.Context, in *editCommentInput) (*socialOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if strings.TrimSpace(in.Body.Body) == "" {
			return nil, huma.Error422UnprocessableEntity("the comment is empty")
		}
		t, _, err := it.load(ctx, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		cid, err := uuid.Parse(in.CommentID)
		if err != nil {
			return nil, huma.Error404NotFound("comment not found")
		}
		if !d.Limits.Comment.Allow(u.ID.String()) {
			return nil, errTooMany
		}
		if err := d.Community.EditComment(ctx, t, cid, u.ID, in.Body.Body); err != nil {
			return nil, communityError(err)
		}
		return social(ctx, t)
	})

	huma.Register(api, huma.Operation{
		OperationID: "delete-" + it.opName + "-comment", Method: http.MethodDelete, Path: it.path + "/{id}/comments/{comment}",
		Summary: "Delete a comment (its author, the owner or a moderator)", Tags: tags,
	}, func(ctx context.Context, in *commentIDInput) (*socialOutput, error) {
		if _, err := requireUser(ctx); err != nil {
			return nil, err
		}
		t, _, err := it.load(ctx, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		cid, err := uuid.Parse(in.CommentID)
		if err != nil {
			return nil, huma.Error404NotFound("comment not found")
		}
		v, _, _ := communityViewer(ctx)
		if err := d.Community.DeleteComment(ctx, t, cid, v); err != nil {
			return nil, communityError(err)
		}
		return social(ctx, t)
	})

	huma.Register(api, huma.Operation{
		OperationID: "update-" + it.opName + "-social", Method: http.MethodPatch, Path: it.path + "/{id}/social",
		Summary: "Switch comments on or off (owner or moderator)", Tags: tags,
	}, func(ctx context.Context, in *socialSettingsInput) (*socialOutput, error) {
		if _, err := requireUser(ctx); err != nil {
			return nil, err
		}
		t, role, err := it.load(ctx, in.ID, "")
		if err != nil {
			return nil, err
		}
		if v, _, _ := communityViewer(ctx); role < access.Owner && !v.Moderator {
			return nil, forbidden(access.Owner, it.opName)
		}
		if err := d.Community.SetCommentsEnabled(ctx, t, in.Body.CommentsEnabled); err != nil {
			return nil, err
		}
		return social(ctx, t)
	})
}

func registerFollows(api huma.API, d Deps) {
	tags := []string{"community"}
	// other returns the logged-in caller and the user named in the path.
	other := func(ctx context.Context, username string) (dbq.User, discover.User, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return u, discover.User{}, err
		}
		o, err := d.Discover.User(ctx, username)
		if errors.Is(err, discover.ErrNotFound) {
			return u, o, huma.Error404NotFound("no such user")
		}
		if err == nil && o.ID == u.ID {
			err = huma.Error422UnprocessableEntity("that is you")
		}
		return u, o, err
	}
	relation := func(ctx context.Context, viewer, o uuid.UUID) (*relationOutput, error) {
		r, err := d.Community.Relation(ctx, viewer, o)
		return &relationOutput{Body: r}, err
	}
	for _, op := range []struct {
		id, method, path, summary string
		do                        func(ctx context.Context, u dbq.User, o uuid.UUID) error
	}{
		{"follow", http.MethodPut, "/users/{username}/follow", "Follow a user; their public hikes appear in the feed",
			func(ctx context.Context, u dbq.User, o uuid.UUID) error { return d.Community.Follow(ctx, u, o) }},
		{"unfollow", http.MethodDelete, "/users/{username}/follow", "Stop following a user",
			func(ctx context.Context, u dbq.User, o uuid.UUID) error { return d.Community.Unfollow(ctx, u.ID, o) }},
		{"block", http.MethodPut, "/users/{username}/block", "Block a user: they cannot comment on your items or follow you, and you no longer see their comments",
			func(ctx context.Context, u dbq.User, o uuid.UUID) error { return d.Community.Block(ctx, u.ID, o) }},
		{"unblock", http.MethodDelete, "/users/{username}/block", "Unblock a user",
			func(ctx context.Context, u dbq.User, o uuid.UUID) error { return d.Community.Unblock(ctx, u.ID, o) }},
	} {
		huma.Register(api, huma.Operation{
			OperationID: op.id, Method: op.method, Path: op.path, Summary: op.summary, Tags: tags,
		}, func(ctx context.Context, in *usernameInput) (*relationOutput, error) {
			u, o, err := other(ctx, in.Username)
			if err != nil {
				return nil, err
			}
			if err := op.do(ctx, u, o.ID); err != nil {
				return nil, communityError(err)
			}
			return relation(ctx, u.ID, o.ID)
		})
	}

	huma.Register(api, huma.Operation{
		OperationID: "list-blocked", Method: http.MethodGet, Path: "/me/blocks",
		Summary: "Users I blocked", Tags: []string{"me"},
	}, func(ctx context.Context, _ *struct{}) (*blockedOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		out := &blockedOutput{}
		out.Body.Users, err = d.Community.Blocked(ctx, u.ID)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-feed", Method: http.MethodGet, Path: "/feed",
		Summary: "Public routes and journeys of the people I follow, newest first", Tags: tags,
	}, func(ctx context.Context, in *feedInput) (*feedOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		before := in.Before
		if before.IsZero() {
			before = time.Now().Add(time.Minute)
		}
		items, err := d.Community.Feed(ctx, u.ID, before, feedPage)
		if err != nil {
			return nil, err
		}
		out := &feedOutput{}
		out.Body.Items = items
		if len(items) == feedPage {
			next := items[len(items)-1].PublishedAt
			out.Body.Next = &next
		}
		return out, nil
	})
}

func registerReports(api huma.API, d Deps) {
	huma.Register(api, huma.Operation{
		OperationID: "report", Method: http.MethodPost, Path: "/reports",
		Summary: "Report a route, journey, comment, photo or user to the moderators", Tags: []string{"community"},
		DefaultStatus: http.StatusNoContent,
	}, func(ctx context.Context, in *reportInput) (*struct{}, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if !d.Limits.Report.Allow(u.ID.String()) {
			return nil, errTooMany
		}
		b := in.Body
		r := community.NewReport{Kind: b.Kind, Reason: b.Reason, Note: strings.TrimSpace(b.Note)}
		switch b.Kind {
		case "route", "journey":
			var t community.Target
			if t, _, err = socialItemFor(d, b.Kind).load(ctx, b.ID, b.Token); err == nil {
				r.TargetID = t.ID
			}
		case "comment":
			if r.TargetID, err = uuid.Parse(b.ID); err != nil {
				err = huma.Error404NotFound("comment not found")
			}
		case "photo":
			err = huma.Error404NotFound("photo not found")
			if id, perr := uuid.Parse(b.ID); perr == nil {
				if t, _, oerr := d.Photos.Owner(ctx, id); oerr == nil {
					if _, _, lerr := socialItemFor(d, t.Kind).load(ctx, t.ID.String(), b.Token); lerr == nil {
						r.TargetID, err = id, nil
					}
				}
			}
		case "user":
			var o discover.User
			if o, err = d.Discover.User(ctx, b.Username); err != nil {
				err = huma.Error404NotFound("no such user")
			}
			r.TargetID = o.ID
		}
		if err != nil {
			return nil, err
		}
		if err := d.Community.Report(ctx, u.ID, r); err != nil {
			return nil, communityError(err)
		}
		return nil, nil
	})

	moderator := func(ctx context.Context) (dbq.User, error) {
		u, err := requireUser(ctx)
		if err == nil && !isModerator(u) {
			err = huma.Error403Forbidden("for moderators")
		}
		return u, err
	}

	huma.Register(api, huma.Operation{
		OperationID: "list-reports", Method: http.MethodGet, Path: "/moderation/reports",
		Summary: "Open reports, oldest first (moderators)", Tags: []string{"moderation"},
	}, func(ctx context.Context, _ *struct{}) (*reportsOutput, error) {
		if _, err := moderator(ctx); err != nil {
			return nil, err
		}
		out := &reportsOutput{}
		var err error
		out.Body.Reports, err = d.Community.OpenReports(ctx)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "resolve-report", Method: http.MethodPost, Path: "/moderation/reports/{id}/resolve",
		Summary: "Close a report and all others on the same target (moderators)", Tags: []string{"moderation"},
		DefaultStatus: http.StatusNoContent,
	}, func(ctx context.Context, in *resolveInput) (*struct{}, error) {
		u, err := moderator(ctx)
		if err != nil {
			return nil, err
		}
		id, err := uuid.Parse(in.ID)
		if err != nil {
			return nil, huma.Error404NotFound("report not found")
		}
		return nil, communityError(d.Community.Resolve(ctx, id, u.ID, in.Body.Resolution))
	})
}
