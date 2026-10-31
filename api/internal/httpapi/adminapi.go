package httpapi

import (
	"context"
	"errors"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/tellbow/alvyo/api/internal/admin"
	"github.com/tellbow/alvyo/api/internal/community"
	"github.com/tellbow/alvyo/api/internal/dbq"
	"github.com/tellbow/alvyo/api/internal/routing"
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

type adminQueryInput struct {
	Q string `query:"q" maxLength:"200" doc:"Name, e-mail address, id, link or a word of the title"`
}

type adminUsersInput struct {
	Q    string `query:"q" maxLength:"200" doc:"Name, display name or e-mail address; all if left out"`
	Page int    `query:"page" minimum:"1" default:"1" doc:"Page of 50 accounts, newest first"`
}

// adminUsersPage is the number of accounts per page.
const adminUsersPage = 50

type adminUsersOutput struct {
	Body struct {
		Users    []admin.User     `json:"users"`
		Counts   admin.UserCounts `json:"counts"`
		PageSize int              `json:"page_size"`
	}
}

type adminItemsOutput struct {
	Body struct {
		Items []admin.Item `json:"items"`
	}
}

type adminLogInput struct {
	Area string `query:"area" enum:"meldungen,nutzer,inhalte,system" doc:"Only this area; all if left out"`
}

type adminLogOutput struct {
	Body struct {
		Entries []admin.LogEntry `json:"entries"`
	}
}

type adminUserInput struct {
	ID string `path:"id" format:"uuid"`
}

type adminRoleInput struct {
	ID   string `path:"id" format:"uuid"`
	Body struct {
		Role string `json:"role" enum:"user,moderator,admin"`
	}
}

type adminItemInput struct {
	Kind string `path:"kind" enum:"route,journey,collection"`
	ID   string `path:"id" format:"uuid"`
}

// adminDoneOutput names the action in «Verlauf», to undo it from there.
type adminDoneOutput struct {
	Body struct {
		LogID string `json:"log_id" format:"uuid"`
	}
}

func adminError(err error) error {
	switch {
	case errors.Is(err, admin.ErrNotFound):
		return huma.Error404NotFound("not found")
	case errors.Is(err, admin.ErrStaff):
		return huma.Error403Forbidden("moderators and admins cannot be banned")
	case errors.Is(err, admin.ErrRole):
		return huma.Error403Forbidden("only admins change roles")
	case errors.Is(err, admin.ErrNoChange):
		return huma.Error409Conflict("nothing to change")
	case errors.Is(err, admin.ErrUndo):
		return huma.Error409Conflict("cannot be undone")
	case errors.Is(err, admin.ErrJob):
		return huma.Error404NotFound("not a job the admin portal runs")
	case errors.Is(err, admin.ErrLater):
		return huma.Error409Conflict("changed again since: undo the later change first")
	}
	return err
}

type adminSystemOutput struct {
	Body struct {
		admin.System
		Services []admin.Service `json:"services"`
		Version  string          `json:"version"`
	}
}

type adminJobsOutput struct {
	Body struct {
		Available bool            `json:"available" doc:"Jobs can be started: in the cluster, with ALVYO_ADMIN_JOBS"`
		Jobs      []admin.CronJob `json:"jobs"`
	}
}

type adminJobInput struct {
	Name string `path:"name" maxLength:"63"`
}

type adminJobOutput struct {
	Body struct {
		Job   string `json:"job" doc:"The Job started"`
		LogID string `json:"log_id" format:"uuid"`
	}
}

type adminStatsOutput struct {
	Body admin.Stats
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

	tags := []string{"admin"}
	done := func(id uuid.UUID, err error) (*adminDoneOutput, error) {
		if err != nil {
			return nil, adminError(err)
		}
		out := &adminDoneOutput{}
		out.Body.LogID = id.String()
		return out, nil
	}
	// userAction runs an action on the user in the path, as a moderator.
	userAction := func(op, path, summary string, act func(ctx context.Context, actor, user uuid.UUID) (uuid.UUID, error)) {
		huma.Register(api, huma.Operation{OperationID: op, Method: http.MethodPost, Path: path, Summary: summary, Tags: tags},
			func(ctx context.Context, in *adminUserInput) (*adminDoneOutput, error) {
				u, err := moderator(ctx)
				if err != nil {
					return nil, err
				}
				return done(act(ctx, u.ID, uuid.MustParse(in.ID)))
			})
	}

	huma.Register(api, huma.Operation{
		OperationID: "admin-users", Method: http.MethodGet, Path: "/admin/users",
		Summary: "Accounts by name or e-mail address, newest first, by pages, with totals (moderators)", Tags: tags,
	}, func(ctx context.Context, in *adminUsersInput) (*adminUsersOutput, error) {
		if _, err := moderator(ctx); err != nil {
			return nil, err
		}
		out := &adminUsersOutput{}
		out.Body.PageSize = adminUsersPage
		var err error
		out.Body.Users, out.Body.Counts, err = d.Admin.Users(ctx, in.Q, adminUsersPage, (in.Page-1)*adminUsersPage)
		return out, err
	})
	userAction("admin-ban", "/admin/users/{id}/ban", "Ban a user: no login, their items private", d.Admin.Ban)
	userAction("admin-unban", "/admin/users/{id}/unban", "Let a banned user log in again", d.Admin.Unban)
	userAction("admin-logout", "/admin/users/{id}/logout", "End all of a user's sessions", d.Admin.EndSessions)
	userAction("admin-verification", "/admin/users/{id}/verification", "Send a new confirmation e-mail",
		func(ctx context.Context, actor, user uuid.UUID) (uuid.UUID, error) {
			u, err := dbq.New(d.DB).GetUserByID(ctx, user)
			if err != nil {
				return uuid.Nil, admin.ErrNotFound
			}
			if u.EmailVerifiedAt != nil {
				return uuid.Nil, admin.ErrNoChange
			}
			if err := d.Auth.SendVerification(ctx, u); err != nil {
				return uuid.Nil, err
			}
			return d.Admin.LogVerificationSent(ctx, actor, user)
		})

	huma.Register(api, huma.Operation{
		OperationID: "admin-role", Method: http.MethodPut, Path: "/admin/users/{id}/role",
		Summary: "Give a user a role (admins; not themselves)", Tags: tags,
	}, func(ctx context.Context, in *adminRoleInput) (*adminDoneOutput, error) {
		u, err := moderator(ctx)
		if err != nil {
			return nil, err
		}
		if u.Role != "admin" {
			return nil, adminError(admin.ErrRole)
		}
		if in.ID == u.ID.String() {
			return nil, huma.Error422UnprocessableEntity("not your own role")
		}
		return done(d.Admin.SetRole(ctx, u.ID, uuid.MustParse(in.ID), in.Body.Role))
	})

	huma.Register(api, huma.Operation{
		OperationID: "admin-items", Method: http.MethodGet, Path: "/admin/items",
		Summary: "Routes, journeys and collections by id, link, owner or title (moderators)", Tags: tags,
	}, func(ctx context.Context, in *adminQueryInput) (*adminItemsOutput, error) {
		if _, err := moderator(ctx); err != nil {
			return nil, err
		}
		out := &adminItemsOutput{}
		var err error
		out.Body.Items, err = d.Admin.Items(ctx, in.Q, 100)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "admin-unpublish", Method: http.MethodPost, Path: "/admin/items/{kind}/{id}/unpublish",
		Summary: "Make a route, journey or collection private", Tags: tags,
	}, func(ctx context.Context, in *adminItemInput) (*adminDoneOutput, error) {
		u, err := moderator(ctx)
		if err != nil {
			return nil, err
		}
		return done(d.Admin.Unpublish(ctx, u.ID, in.Kind, uuid.MustParse(in.ID)))
	})

	huma.Register(api, huma.Operation{
		OperationID: "admin-retrail", Method: http.MethodPost, Path: "/admin/items/{kind}/{id}/retrail",
		Summary:     "Match a route, or a journey's stage routes, to the trail network again",
		Description: "For routes planned while the network was missing or outdated; as `alvyo route retrail` for one item.",
		Tags:        tags,
	}, func(ctx context.Context, in *adminItemInput) (*adminDoneOutput, error) {
		u, err := moderator(ctx)
		if err != nil {
			return nil, err
		}
		id := uuid.MustParse(in.ID)
		var rows pgx.Rows
		switch in.Kind {
		case "route":
			rows, err = d.DB.Query(ctx, `SELECT id FROM routes WHERE id = $1`, id)
		case "journey":
			rows, err = d.DB.Query(ctx, `SELECT id FROM routes WHERE journey_id = $1`, id)
		default:
			return nil, huma.Error422UnprocessableEntity("only routes and journeys")
		}
		if err != nil {
			return nil, err
		}
		ids, err := pgx.CollectRows(rows, pgx.RowTo[uuid.UUID])
		if err != nil {
			return nil, err
		}
		if len(ids) == 0 && in.Kind == "route" {
			return nil, adminError(admin.ErrNotFound)
		}
		changed, m := 0, &routing.TrailMatcher{DB: d.DB}
		for _, r := range ids {
			ok, err := d.Routes.RetrailOne(ctx, m, r)
			if err != nil {
				return nil, err
			}
			if ok {
				changed++
			}
		}
		if changed == 0 {
			return nil, adminError(admin.ErrNoChange)
		}
		return done(d.Admin.LogRetrail(ctx, u.ID, in.Kind, id, changed))
	})

	huma.Register(api, huma.Operation{
		OperationID: "admin-log", Method: http.MethodGet, Path: "/admin/log",
		Summary: "The admin portal's actions, newest first (moderators)", Tags: tags,
	}, func(ctx context.Context, in *adminLogInput) (*adminLogOutput, error) {
		if _, err := moderator(ctx); err != nil {
			return nil, err
		}
		out := &adminLogOutput{}
		var err error
		out.Body.Entries, err = d.Admin.Log(ctx, in.Area, 200)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "admin-undo", Method: http.MethodPost, Path: "/admin/log/{id}/undo",
		Summary: "Undo an action, unless changed again since (a change of role: admins)", Tags: tags,
		DefaultStatus: http.StatusNoContent,
	}, func(ctx context.Context, in *adminUserInput) (*struct{}, error) {
		u, err := moderator(ctx)
		if err != nil {
			return nil, err
		}
		return nil, adminError(d.Admin.Undo(ctx, u.ID, uuid.MustParse(in.ID), u.Role == "admin"))
	})

	huma.Register(api, huma.Operation{
		OperationID: "admin-system", Method: http.MethodGet, Path: "/admin/system",
		Summary: "Outside services, how fresh the jobs' data is, versions (moderators)", Tags: tags,
	}, func(ctx context.Context, _ *struct{}) (*adminSystemOutput, error) {
		if _, err := moderator(ctx); err != nil {
			return nil, err
		}
		out := &adminSystemOutput{}
		out.Body.Version = d.Version
		out.Body.Services = admin.Services(ctx, d.Admin.Probes)
		var err error
		out.Body.System, err = d.Admin.SystemInfo(ctx)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "admin-stats", Method: http.MethodGet, Path: "/admin/stats",
		Summary: "Accounts and tours, in total and for each of the last 12 weeks (moderators)", Tags: tags,
	}, func(ctx context.Context, _ *struct{}) (*adminStatsOutput, error) {
		if _, err := moderator(ctx); err != nil {
			return nil, err
		}
		out := &adminStatsOutput{}
		var err error
		out.Body, err = d.Admin.Stats(ctx, 12)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "admin-jobs", Method: http.MethodGet, Path: "/admin/jobs",
		Summary: "The cron jobs: schedule, last start and success (moderators)", Tags: tags,
	}, func(ctx context.Context, _ *struct{}) (*adminJobsOutput, error) {
		if _, err := moderator(ctx); err != nil {
			return nil, err
		}
		out := &adminJobsOutput{}
		out.Body.Jobs = []admin.CronJob{}
		if d.Admin.Kube == nil {
			return out, nil
		}
		out.Body.Available = true
		var err error
		out.Body.Jobs, err = d.Admin.Kube.CronJobs(ctx)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "admin-run-job", Method: http.MethodPost, Path: "/admin/jobs/{name}/run",
		Summary: "Start a cron job now, as `kubectl create job --from=cronjob/…` (admins)", Tags: tags,
	}, func(ctx context.Context, in *adminJobInput) (*adminJobOutput, error) {
		u, err := moderator(ctx)
		if err != nil {
			return nil, err
		}
		if u.Role != "admin" {
			return nil, huma.Error403Forbidden("for admins")
		}
		job, id, err := d.Admin.RunLogged(ctx, u.ID, in.Name)
		if err != nil {
			return nil, adminError(err)
		}
		out := &adminJobOutput{}
		out.Body.Job, out.Body.LogID = job, id.String()
		return out, nil
	})
}
