package httpapi

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/community"
	"github.com/tellbow/alvyo/api/internal/dbq"
)

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

// registerAdmin adds the admin portal's endpoints (NewAdmin only).
func registerAdmin(api huma.API, d Deps) {
	moderator := func(ctx context.Context) (dbq.User, error) {
		u, err := requireUser(ctx)
		if err == nil && !isModerator(ctx, u) {
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
