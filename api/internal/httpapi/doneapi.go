package httpapi

import (
	"context"
	"net/http"
	"time"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/auth"
	"github.com/tellbow/alvyo/api/internal/done"
)

type markDoneInput struct {
	ID    string `path:"id" format:"uuid"`
	Token string `query:"t" doc:"Share token of an unlisted item"`
	Body  *struct {
		DoneOn string `json:"done_on,omitempty" format:"date" doc:"The day; today (Swiss time) if left out"`
	} `required:"false"`
}

func (in *markDoneInput) Resolve(huma.Context) []error {
	if in.Body == nil || in.Body.DoneOn == "" {
		return nil
	}
	d, err := time.Parse(time.DateOnly, in.Body.DoneOn)
	if err != nil || d.After(swissToday()) || d.Year() < 1900 {
		return []error{&huma.ErrorDetail{Location: "body.done_on", Message: "a day up to today", Value: in.Body.DoneOn}}
	}
	return nil
}

type unmarkDoneInput struct {
	ID    string `path:"id" format:"uuid"`
	Token string `query:"t" doc:"Share token of an unlisted item"`
}

type doneOutput struct {
	Body struct {
		DoneOn     *string `json:"done_on,omitempty" format:"date" doc:"When the viewer hiked it, if they did"`
		DoneMarked bool    `json:"done_marked" doc:"By their own mark, which can be taken back"`
	}
}

var zurich, _ = time.LoadLocation("Europe/Zurich")

func swissToday() time.Time {
	y, m, d := time.Now().In(zurich).Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}

// day formats a date of the database (YYYY-MM-DD).
func day(t *time.Time) *string {
	if t == nil {
		return nil
	}
	s := t.Format(time.DateOnly)
	return &s
}

// viewerID is the logged-in user, or uuid.Nil.
func viewerID(ctx context.Context) uuid.UUID {
	u, _ := auth.UserFrom(ctx)
	return u.ID
}

// registerDone: «Gewandert», a mark any user sets on a route or journey
// they can see; recorded hikes and ticked-off stages count without one.
func registerDone(api huma.API, d Deps) {
	tags := []string{"done"}
	// target checks access and gives what is marked.
	target := func(ctx context.Context, k done.Kind, id, token string) (uuid.UUID, error) {
		if k == done.Journey {
			j, _, err := loadJourney(ctx, d, id, token)
			return uuid.MustParse(j.ID), err
		}
		r, _, err := loadRoute(ctx, d, id, token)
		if err == nil && r.JourneyID != "" {
			return uuid.Nil, huma.Error422UnprocessableEntity("a stage is ticked off on its journey")
		}
		return uuid.MustParse(r.ID), err
	}
	state := func(ctx context.Context, user uuid.UUID, k done.Kind, id uuid.UUID) (*doneOutput, error) {
		st, err := d.Done.Of(ctx, user, k, id)
		out := &doneOutput{}
		out.Body.DoneOn, out.Body.DoneMarked = day(st.On), st.Marked
		return out, err
	}
	for _, k := range []done.Kind{done.Route, done.Journey} {
		path := "/" + string(k) + "s/{id}/done"
		huma.Register(api, huma.Operation{
			OperationID: "mark-" + string(k) + "-done", Method: http.MethodPut, Path: path,
			Summary: "Mark a " + string(k) + " as hiked, on a day", Tags: tags,
		}, func(ctx context.Context, in *markDoneInput) (*doneOutput, error) {
			u, err := requireUser(ctx)
			if err != nil {
				return nil, err
			}
			id, err := target(ctx, k, in.ID, in.Token)
			if err != nil {
				return nil, err
			}
			on := swissToday()
			if in.Body != nil && in.Body.DoneOn != "" {
				on, _ = time.Parse(time.DateOnly, in.Body.DoneOn)
			}
			if err := d.Done.Mark(ctx, u.ID, k, id, on); err != nil {
				return nil, err
			}
			return state(ctx, u.ID, k, id)
		})
		huma.Register(api, huma.Operation{
			OperationID: "unmark-" + string(k) + "-done", Method: http.MethodDelete, Path: path,
			Summary: "Take back one's mark; a recorded hike still counts", Tags: tags,
		}, func(ctx context.Context, in *unmarkDoneInput) (*doneOutput, error) {
			u, err := requireUser(ctx)
			if err != nil {
				return nil, err
			}
			id, err := target(ctx, k, in.ID, in.Token)
			if err != nil {
				return nil, err
			}
			if err := d.Done.Unmark(ctx, u.ID, k, id); err != nil {
				return nil, err
			}
			return state(ctx, u.ID, k, id)
		})
	}
}

// doneDays sets when the viewer hiked the n items of a list (id(i)) that
// they hiked (set(i, day)).
func doneDays(ctx context.Context, d Deps, viewer uuid.UUID, k done.Kind, n int, id func(int) string, set func(int, *string)) error {
	ids := make([]uuid.UUID, n)
	for i := range n {
		ids[i] = uuid.MustParse(id(i))
	}
	days, err := d.Done.Days(ctx, viewer, k, ids)
	if err != nil {
		return err
	}
	for i, x := range ids {
		if t, ok := days[x]; ok {
			set(i, day(&t))
		}
	}
	return nil
}
