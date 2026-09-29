package httpapi

import (
	"context"
	"net/http"
	"time"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/reminders"
)

type reminder struct {
	Kind string `json:"kind" enum:"book,weather,start" doc:"Book the nights (three weeks before), the weather (two days before), the start (the day before)"`
	Day  string `json:"day" format:"date"`
}

type remindersOutput struct {
	Body struct {
		On bool `json:"on" doc:"Whether the caller gets the reminders by e-mail (the owner and the people along)"`
		// Start is the first planned stage's day; the reminders come before it.
		Start    string     `json:"start,omitempty" format:"date"`
		Upcoming []reminder `json:"upcoming" doc:"The reminders still to come, by day"`
	}
}

type setRemindersInput struct {
	ID   string `path:"id" format:"uuid"`
	Body struct {
		On bool `json:"on"`
	}
}

func registerReminders(api huma.API, d Deps) {
	tags := []string{"journeys"}
	zurich, err := time.LoadLocation("Europe/Zurich")
	if err != nil {
		panic(err) // cannot happen: time/tzdata is linked in
	}
	answer := func(ctx context.Context, rawID string) (*remindersOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		j, _, err := loadJourney(ctx, d, rawID, "")
		if err != nil {
			return nil, err
		}
		out := &remindersOutput{}
		out.Body.Upcoming = []reminder{}
		if out.Body.On, err = d.Reminders.On(ctx, uuid.MustParse(j.ID), u.ID); err != nil {
			return nil, err
		}
		for _, st := range j.StageList {
			if st.Status == "planned" && st.PlannedDate != nil && (out.Body.Start == "" || *st.PlannedDate < out.Body.Start) {
				out.Body.Start = *st.PlannedDate
			}
		}
		if start, err := time.Parse(time.DateOnly, out.Body.Start); err == nil {
			today := time.Now().In(zurich).Format(time.DateOnly)
			for _, k := range reminders.Kinds {
				if day := start.AddDate(0, 0, -k.Before).Format(time.DateOnly); day >= today {
					out.Body.Upcoming = append(out.Body.Upcoming, reminder{Kind: k.Kind, Day: day})
				}
			}
		}
		return out, nil
	}

	huma.Register(api, huma.Operation{
		OperationID: "journey-reminders", Method: http.MethodGet, Path: "/journeys/{id}/reminders",
		Summary: "Reminders before the journey starts, for the caller", Tags: tags,
	}, func(ctx context.Context, in *itemInput) (*remindersOutput, error) {
		return answer(ctx, in.ID)
	})

	huma.Register(api, huma.Operation{
		OperationID: "set-journey-reminders", Method: http.MethodPut, Path: "/journeys/{id}/reminders",
		Summary: "Turn the caller's reminders by e-mail on or off", Tags: tags,
	}, func(ctx context.Context, in *setRemindersInput) (*remindersOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		j, _, err := loadJourney(ctx, d, in.ID, "")
		if err != nil {
			return nil, err
		}
		if err := d.Reminders.Set(ctx, uuid.MustParse(j.ID), u.ID, in.Body.On); err != nil {
			return nil, err
		}
		return answer(ctx, in.ID)
	})
}
