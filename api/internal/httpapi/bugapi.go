package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/bugs"
)

type bugReportInput struct {
	Body struct {
		Description string `json:"description" minLength:"1" maxLength:"4000"`
		Place       string `json:"place" maxLength:"500" doc:"The page's address or the app's screen, and the item open"`
		Version     string `json:"version" maxLength:"60"`
		Platform    string `json:"platform" enum:"web,ios,android"`
		Screenshot  []byte `json:"screenshot,omitempty" doc:"PNG or JPEG, base64, up to 4 MB"`
	}
}

type bugReportOutput struct {
	Body struct {
		ID       string `json:"id" format:"uuid"`
		IssueURL string `json:"issue_url,omitempty" doc:"The GitHub issue, when one was opened"`
	}
}

func registerBugReports(api huma.API, d Deps) {
	tags := []string{"bugs"}
	huma.Register(api, huma.Operation{
		OperationID: "report-bug", Method: http.MethodPost, Path: "/bug-reports",
		Summary:     "Report a bug, with what is open and a screenshot",
		Description: "Opens an issue on GitHub; the screenshot stays with us. A few a day per person.",
		Tags:        tags, DefaultStatus: http.StatusCreated, MaxBodyBytes: bugs.MaxScreenshotBytes*4/3 + 1<<20,
	}, func(ctx context.Context, in *bugReportInput) (*bugReportOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if len(in.Body.Screenshot) > bugs.MaxScreenshotBytes {
			return nil, huma.Error413RequestEntityTooLarge("screenshot too large")
		}
		if strings.TrimSpace(in.Body.Description) == "" {
			return nil, huma.Error422UnprocessableEntity("say what happened")
		}
		if !d.Limits.BugReport.Allow(u.ID.String()) {
			return nil, errTooMany
		}
		b := in.Body
		id, issue, err := d.Bugs.Create(ctx, bugs.Report{
			UserID: u.ID, Username: u.Username, Description: b.Description, Place: b.Place,
			Version: b.Version, Platform: b.Platform, Screenshot: b.Screenshot,
		})
		if errors.Is(err, bugs.ErrScreenshot) {
			return nil, huma.Error422UnprocessableEntity(err.Error())
		}
		if err != nil {
			return nil, err
		}
		out := &bugReportOutput{}
		out.Body.ID, out.Body.IssueURL = id.String(), issue
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "bug-screenshot", Method: http.MethodGet, Path: "/bug-reports/{id}/screenshot",
		Summary: "A bug report's screenshot (moderators)", Tags: tags,
	}, func(ctx context.Context, in *struct {
		ID string `path:"id" format:"uuid"`
	}) (*imageOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if !isModerator(u) {
			return nil, huma.Error403Forbidden("for moderators")
		}
		id, err := uuid.Parse(in.ID)
		if err != nil {
			return nil, huma.Error404NotFound("no such screenshot")
		}
		b, kind, err := d.Bugs.Screenshot(ctx, id)
		if errors.Is(err, bugs.ErrNotFound) {
			return nil, huma.Error404NotFound("no such screenshot")
		}
		if err != nil {
			return nil, err
		}
		return &imageOutput{ContentType: kind, CacheControl: "private, no-store", Body: b}, nil
	})
}
