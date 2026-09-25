package httpapi

import (
	"archive/zip"
	"bytes"
	"context"
	"errors"
	"fmt"
	"mime"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/access"
	"github.com/tellbow/alvyo/api/internal/auth"
	"github.com/tellbow/alvyo/api/internal/gpx"
	"github.com/tellbow/alvyo/api/internal/journeys"
	"github.com/tellbow/alvyo/api/internal/og"
	"github.com/tellbow/alvyo/api/internal/routes"
	"github.com/tellbow/alvyo/api/internal/routing"
)

type journeyBody struct {
	journeys.Journey
	Role       string `json:"role" enum:"owner,editor,viewer"`
	CanEdit    bool   `json:"can_edit"`
	ShareToken string `json:"share_token,omitempty" doc:"Owner only; the link is /journeys/{id}?t=token"`
}

type journeyOutput struct {
	ETag string `header:"ETag"`
	Body journeyBody
}

type journeyIDInput struct {
	ID    string `path:"id" format:"uuid"`
	Token string `query:"t" doc:"Share token of an unlisted journey"`
}

// plannedStageInput is a stage with its route, as POST /journeys/plan
// proposes it.
type plannedStageInput struct {
	Title         string          `json:"title,omitempty" maxLength:"120"`
	Profile       string          `json:"profile" enum:"hike,alpine"`
	Anchors       []routes.Anchor `json:"anchors" minItems:"2" maxItems:"200"`
	Legs          []routing.Leg   `json:"legs" minItems:"1" maxItems:"199"`
	StartPlaceID  string          `json:"start_place_id,omitempty" format:"uuid"`
	EndPlaceID    string          `json:"end_place_id,omitempty" format:"uuid"`
	Accommodation string          `json:"accommodation,omitempty" maxLength:"200"`
}

type createJourneyInput struct {
	Body struct {
		Title       string              `json:"title" minLength:"1" maxLength:"120"`
		Description string              `json:"description,omitempty" maxLength:"5000"`
		Visibility  string              `json:"visibility,omitempty" enum:"private,unlisted,public" default:"private"`
		Tags        []string            `json:"tags,omitempty" maxItems:"20" doc:"At most 20, each up to 40 characters; repeats (ignoring case) are dropped"`
		Stages      []plannedStageInput `json:"stages,omitempty" maxItems:"400" doc:"The stages with their routes, e.g. from POST /journeys/plan"`
	}
}

type updateJourneyInput struct {
	ID      string `path:"id" format:"uuid"`
	IfMatch string `header:"If-Match" required:"true"`
	Body    struct {
		Title       *string  `json:"title,omitempty" minLength:"1" maxLength:"120"`
		Description *string  `json:"description,omitempty" maxLength:"5000"`
		Visibility  *string  `json:"visibility,omitempty" enum:"private,unlisted,public"`
		Tags        []string `json:"tags,omitempty" maxItems:"20" doc:"Replaces the tags; [] removes them"`
	}
}

type addStageInput struct {
	ID   string `path:"id" format:"uuid"`
	Body struct {
		Title       string  `json:"title,omitempty" maxLength:"120"`
		Position    *int    `json:"position,omitempty" minimum:"0" doc:"0-based; appended if omitted"`
		CopyRouteID *string `json:"copy_route_id,omitempty" format:"uuid" doc:"Copy one of your routes into the stage"`
	}
}

type updateStageInput struct {
	ID      string `path:"id" format:"uuid"`
	StageID string `path:"stage" format:"uuid"`
	IfMatch string `header:"If-Match" required:"true" doc:"The stage's version the change is based on"`
	Body    struct {
		Title          *string `json:"title,omitempty" maxLength:"120"`
		PlannedDate    *string `json:"planned_date,omitempty" pattern:"^(\\d{4}-\\d{2}-\\d{2})?$" doc:"YYYY-MM-DD, empty to clear"`
		Status         *string `json:"status,omitempty" enum:"planned,done,skipped"`
		DoneOn         *string `json:"done_on,omitempty" pattern:"^(\\d{4}-\\d{2}-\\d{2})?$"`
		TransferBefore *string `json:"transfer_before,omitempty" enum:"pt,cablecar,other," doc:"How the gap to the previous stage is covered; empty to clear"`
		Notes          *string `json:"notes,omitempty" maxLength:"5000"`
		StartPlaceID   *string `json:"start_place_id,omitempty" pattern:"^([0-9a-f-]{36})?$" doc:"A place id; empty for the suggestion"`
		EndPlaceID     *string `json:"end_place_id,omitempty" pattern:"^([0-9a-f-]{36})?$" doc:"A place id; empty for the suggestion"`
		Accommodation  *string `json:"accommodation,omitempty" maxLength:"200"`
		Booked         *bool   `json:"accommodation_booked,omitempty"`
	}
}

// Resolve rejects dates and place ids that only look right (the patterns let
// 2026-02-30 through), which the database would refuse.
func (in *updateStageInput) Resolve(huma.Context) []error {
	var errs []error
	check := func(field string, v *string, ok func(string) bool) {
		if v != nil && *v != "" && !ok(*v) {
			errs = append(errs, &huma.ErrorDetail{Location: "body." + field, Message: "invalid value", Value: *v})
		}
	}
	date := func(v string) bool { _, err := time.Parse(time.DateOnly, v); return err == nil }
	id := func(v string) bool { _, err := uuid.Parse(v); return err == nil }
	check("planned_date", in.Body.PlannedDate, date)
	check("done_on", in.Body.DoneOn, date)
	check("start_place_id", in.Body.StartPlaceID, id)
	check("end_place_id", in.Body.EndPlaceID, id)
	return errs
}

type stageIDInput struct {
	ID      string `path:"id" format:"uuid"`
	StageID string `path:"stage" format:"uuid"`
}

type reorderInput struct {
	ID   string `path:"id" format:"uuid"`
	Body struct {
		StageIDs []string `json:"stage_ids" maxItems:"400"`
	}
}

type stageRouteInput struct {
	ID      string `path:"id" format:"uuid"`
	StageID string `path:"stage" format:"uuid"`
	Body    struct {
		Profile string          `json:"profile" enum:"hike,alpine"`
		Anchors []routes.Anchor `json:"anchors" minItems:"2" maxItems:"200"`
		Legs    []routing.Leg   `json:"legs" minItems:"1" maxItems:"199"`
	}
}

type journeyListOutput struct {
	Body struct {
		Journeys []journeys.Summary `json:"journeys"`
	}
}

type zipOutput struct {
	ContentType        string `header:"Content-Type"`
	ContentDisposition string `header:"Content-Disposition"`
	Body               []byte
}

func registerJourneys(api huma.API, d Deps) {
	tags := []string{"journeys"}
	store := d.Journeys

	huma.Register(api, huma.Operation{
		OperationID: "create-journey", Method: http.MethodPost, Path: "/journeys",
		Summary: "Start a multi-day journey, empty or with its stages", Tags: tags, DefaultStatus: http.StatusCreated,
		MaxBodyBytes: 4 * routeBodyLimit,
	}, func(ctx context.Context, in *createJourneyInput) (*journeyOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if err := checkPublish(u, in.Body.Visibility); err != nil {
			return nil, err
		}
		labels, err := normalizeTags(in.Body.Tags)
		if err != nil {
			return nil, err
		}
		stages := make([]journeys.PlannedStage, len(in.Body.Stages))
		for i, st := range in.Body.Stages {
			stages[i] = journeys.PlannedStage{
				Title:        strings.TrimSpace(st.Title),
				Content:      routes.Content{Profile: st.Profile, Anchors: st.Anchors, Legs: st.Legs},
				StartPlaceID: optionalID(st.StartPlaceID), EndPlaceID: optionalID(st.EndPlaceID),
				Accommodation: strings.TrimSpace(st.Accommodation),
			}
		}
		j, err := store.CreatePlanned(ctx, u.ID, journeys.Meta{
			Title: strings.TrimSpace(in.Body.Title), Description: in.Body.Description, Visibility: in.Body.Visibility,
			Tags: labels,
		}, stages)
		if err != nil {
			return nil, journeyError(err)
		}
		return journeyResponse(j, access.Owner), nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "list-my-journeys", Method: http.MethodGet, Path: "/journeys",
		Summary: "The logged-in user's journeys", Tags: tags,
	}, func(ctx context.Context, _ *struct{}) (*journeyListOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		list, err := store.ListByOwner(ctx, u.ID)
		if err != nil {
			return nil, err
		}
		out := &journeyListOutput{}
		out.Body.Journeys = list
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-journey", Method: http.MethodGet, Path: "/journeys/{id}",
		Summary: "A journey with its stages, totals, progress and profile", Tags: tags,
	}, func(ctx context.Context, in *journeyIDInput) (*journeyOutput, error) {
		j, role, err := loadJourney(ctx, d, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		return journeyResponse(j, role), nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-journey-image", Method: http.MethodGet, Path: "/journeys/{id}/og.png",
		Summary:     "Preview image of a journey for link previews (1200×630)",
		Description: "404 while no stage has a route.",
		Tags:        tags,
	}, func(ctx context.Context, in *journeyIDInput) (*imageOutput, error) {
		j, _, err := loadJourney(ctx, d, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		card := og.Card{Title: j.Title, Stats: cardStats(j.Totals), Ends: true}
		for _, s := range j.StageList {
			if s.Route != nil {
				card.Lines = append(card.Lines, s.Route.Line)
			}
		}
		if len(card.Lines) == 0 {
			return nil, huma.Error404NotFound("no stage has a route yet")
		}
		b, err := d.Images.PNG(imageKey(j.ID, card), card)
		if err != nil {
			return nil, err
		}
		cache := "private, max-age=3600" // not in shared caches unless anyone may see it
		if j.Visibility == "public" {
			cache = "public, max-age=3600"
		}
		return &imageOutput{ContentType: "image/png", CacheControl: cache, Body: b}, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "update-journey", Method: http.MethodPatch, Path: "/journeys/{id}",
		Summary: "Change a journey's title, description, visibility or tags", Tags: tags,
	}, func(ctx context.Context, in *updateJourneyInput) (*journeyOutput, error) {
		j, role, err := journeyAs(ctx, d, in.ID, access.Editor)
		if err != nil {
			return nil, err
		}
		version, err := strconv.Atoi(strings.Trim(strings.TrimPrefix(in.IfMatch, "W/"), `"`))
		if err != nil {
			return nil, huma.Error400BadRequest("If-Match must be the journey version")
		}
		m := j.Meta
		if in.Body.Title != nil {
			m.Title = strings.TrimSpace(*in.Body.Title)
		}
		if in.Body.Description != nil {
			m.Description = *in.Body.Description
		}
		if in.Body.Tags != nil {
			if m.Tags, err = normalizeTags(in.Body.Tags); err != nil {
				return nil, err
			}
		}
		if in.Body.Visibility != nil && *in.Body.Visibility != j.Visibility && role < access.Owner {
			return nil, forbidden(access.Owner, "journey")
		}
		if in.Body.Visibility != nil && *in.Body.Visibility != j.Visibility {
			u, _ := auth.UserFrom(ctx)
			if err := checkPublish(u, *in.Body.Visibility); err != nil {
				return nil, err
			}
			m.Visibility = *in.Body.Visibility
		}
		j, err = store.UpdateMeta(ctx, uuid.MustParse(j.ID), version, m)
		if err != nil {
			return nil, journeyError(err)
		}
		return journeyResponse(j, role), nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "delete-journey", Method: http.MethodDelete, Path: "/journeys/{id}",
		Summary: "Delete a journey with all its stages and their routes", Tags: tags, DefaultStatus: http.StatusNoContent,
	}, func(ctx context.Context, in *journeyIDInput) (*struct{}, error) {
		j, _, err := journeyAs(ctx, d, in.ID, access.Owner)
		if err != nil {
			return nil, err
		}
		return nil, journeyError(store.Delete(ctx, uuid.MustParse(j.ID)))
	})

	huma.Register(api, huma.Operation{
		OperationID: "rotate-journey-link", Method: http.MethodPost, Path: "/journeys/{id}/link/rotate",
		Summary: "Replace the share link; the old link stops working", Tags: tags,
	}, func(ctx context.Context, in *journeyIDInput) (*shareTokenOutput, error) {
		j, _, err := journeyAs(ctx, d, in.ID, access.Owner)
		if err != nil {
			return nil, err
		}
		token, err := store.RotateShareToken(ctx, uuid.MustParse(j.ID))
		if err != nil {
			return nil, err
		}
		out := &shareTokenOutput{}
		out.Body.ShareToken = token
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "add-stage", Method: http.MethodPost, Path: "/journeys/{id}/stages",
		Summary: "Add a stage (empty, or with a copy of one of your routes)", Tags: tags,
	}, func(ctx context.Context, in *addStageInput) (*journeyOutput, error) {
		j, role, err := journeyAs(ctx, d, in.ID, access.Editor)
		if err != nil {
			return nil, err
		}
		u, _ := auth.UserFrom(ctx)
		n := journeys.NewStage{Title: strings.TrimSpace(in.Body.Title), Position: in.Body.Position}
		if in.Body.CopyRouteID != nil {
			id, err := uuid.Parse(*in.Body.CopyRouteID)
			if err != nil {
				return nil, huma.Error422UnprocessableEntity("invalid route id")
			}
			n.CopyFrom = &id
		}
		return mutateJourney(ctx, store, j, role, store.AddStage(ctx, uuid.MustParse(j.ID), u.ID, n))
	})

	huma.Register(api, huma.Operation{
		OperationID: "update-stage", Method: http.MethodPatch, Path: "/journeys/{id}/stages/{stage}",
		Summary: "Change a stage's title, date, status, transfer, places, accommodation or notes", Tags: tags,
	}, func(ctx context.Context, in *updateStageInput) (*journeyOutput, error) {
		j, role, err := journeyAs(ctx, d, in.ID, access.Editor)
		if err != nil {
			return nil, err
		}
		sid, err := uuid.Parse(in.StageID)
		if err != nil {
			return nil, huma.Error404NotFound("stage not found")
		}
		version, err := strconv.Atoi(strings.Trim(strings.TrimPrefix(in.IfMatch, "W/"), `"`))
		if err != nil {
			return nil, huma.Error400BadRequest("If-Match must be the stage version")
		}
		b := in.Body
		return mutateJourney(ctx, store, j, role, store.UpdateStage(ctx, uuid.MustParse(j.ID), sid, version, journeys.StagePatch{
			Title: b.Title, PlannedDate: b.PlannedDate, Status: b.Status, DoneOn: b.DoneOn,
			TransferBefore: b.TransferBefore, Notes: b.Notes,
			StartPlaceID: b.StartPlaceID, EndPlaceID: b.EndPlaceID, Accommodation: b.Accommodation, Booked: b.Booked,
		}))
	})

	huma.Register(api, huma.Operation{
		OperationID: "delete-stage", Method: http.MethodDelete, Path: "/journeys/{id}/stages/{stage}",
		Summary: "Delete a stage and its route", Tags: tags,
	}, func(ctx context.Context, in *stageIDInput) (*journeyOutput, error) {
		j, role, err := journeyAs(ctx, d, in.ID, access.Editor)
		if err != nil {
			return nil, err
		}
		sid, err := uuid.Parse(in.StageID)
		if err != nil {
			return nil, huma.Error404NotFound("stage not found")
		}
		return mutateJourney(ctx, store, j, role, store.DeleteStage(ctx, uuid.MustParse(j.ID), sid))
	})

	huma.Register(api, huma.Operation{
		OperationID: "reorder-stages", Method: http.MethodPut, Path: "/journeys/{id}/stages/order",
		Summary: "Set the order of all stages", Tags: tags,
	}, func(ctx context.Context, in *reorderInput) (*journeyOutput, error) {
		j, role, err := journeyAs(ctx, d, in.ID, access.Editor)
		if err != nil {
			return nil, err
		}
		ids := make([]uuid.UUID, len(in.Body.StageIDs))
		for i, raw := range in.Body.StageIDs {
			if ids[i], err = uuid.Parse(raw); err != nil {
				return nil, huma.Error422UnprocessableEntity("invalid stage id")
			}
		}
		return mutateJourney(ctx, store, j, role, store.Reorder(ctx, uuid.MustParse(j.ID), ids))
	})

	huma.Register(api, huma.Operation{
		OperationID: "create-stage-route", Method: http.MethodPost, Path: "/journeys/{id}/stages/{stage}/route",
		Summary:     "Save the planned route of a stage",
		Description: "For a stage without a route. Later changes go through PATCH /routes/{id}.",
		Tags:        tags, MaxBodyBytes: routeBodyLimit,
	}, func(ctx context.Context, in *stageRouteInput) (*journeyOutput, error) {
		j, role, err := journeyAs(ctx, d, in.ID, access.Editor)
		if err != nil {
			return nil, err
		}
		sid, err := uuid.Parse(in.StageID)
		if err != nil {
			return nil, huma.Error404NotFound("stage not found")
		}
		title := j.Title
		for i, st := range j.StageList {
			if st.ID == sid.String() {
				title = stageTitle(j, i)
			}
		}
		// The journey owner owns stage routes, whoever plans them.
		_, err = store.SetStageRoute(ctx, uuid.MustParse(j.ID), sid, uuid.MustParse(j.OwnerID), title,
			routes.Content{Profile: in.Body.Profile, Anchors: in.Body.Anchors, Legs: in.Body.Legs})
		return mutateJourney(ctx, store, j, role, err)
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-journey-gpx", Method: http.MethodGet, Path: "/journeys/{id}/gpx",
		Summary: "All stage routes as GPX files in a zip", Tags: tags,
	}, func(ctx context.Context, in *journeyIDInput) (*zipOutput, error) {
		j, _, err := loadJourney(ctx, d, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		var buf bytes.Buffer
		zw := zip.NewWriter(&buf)
		for i, st := range j.StageList {
			if st.Route == nil {
				continue
			}
			r, err := d.Routes.Get(ctx, uuid.MustParse(st.Route.ID))
			if err != nil {
				return nil, err
			}
			name := stageTitle(j, i)
			f, err := zw.Create(fmt.Sprintf("%02d-%s", i+1, gpx.Filename(name)))
			if err != nil {
				return nil, err
			}
			if err := gpx.Write(f, gpx.Track{
				Name: name, Author: j.OwnerUsername, Link: d.PublicURL + "/journeys/" + j.ID,
				Points: r.Line(), Time: r.UpdatedAt,
			}); err != nil {
				return nil, err
			}
		}
		if err := zw.Close(); err != nil {
			return nil, err
		}
		return &zipOutput{
			ContentType:        "application/zip",
			ContentDisposition: mime.FormatMediaType("attachment", map[string]string{"filename": strings.TrimSuffix(gpx.Filename(j.Title), ".gpx") + ".zip"}),
			Body:               buf.Bytes(),
		}, nil
	})
}

// optionalID parses an id checked by the input's format; "" is none.
func optionalID(s string) *uuid.UUID {
	id, err := uuid.Parse(s)
	if err != nil {
		return nil
	}
	return &id
}

// stageTitle is the stage's own title or "<journey> – <n>".
func stageTitle(j journeys.Journey, i int) string {
	if t := j.StageList[i].Title; t != "" {
		return t
	}
	return fmt.Sprintf("%s – %d", j.Title, i+1)
}

// mutateJourney reports the store error of a stage change or the updated
// journey.
func mutateJourney(ctx context.Context, store *journeys.Store, j journeys.Journey, role access.Role, err error) (*journeyOutput, error) {
	if err != nil {
		return nil, journeyError(err)
	}
	updated, err := store.Get(ctx, uuid.MustParse(j.ID))
	if err != nil {
		return nil, journeyError(err)
	}
	return journeyResponse(updated, role), nil
}

func journeyResponse(j journeys.Journey, role access.Role) *journeyOutput {
	body := journeyBody{Journey: j, Role: role.String(), CanEdit: role >= access.Editor}
	if role == access.Owner && j.Visibility == "unlisted" {
		body.ShareToken = j.ShareToken
	}
	return &journeyOutput{ETag: strconv.Quote(strconv.Itoa(j.Version)), Body: body}
}

func journeyError(err error) error {
	switch {
	case err == nil:
		return nil
	case errors.Is(err, journeys.ErrNotFound):
		return huma.Error404NotFound("journey not found")
	case errors.Is(err, journeys.ErrStageNotFound):
		return huma.Error404NotFound("stage not found")
	case errors.Is(err, journeys.ErrVersion):
		return huma.Error412PreconditionFailed("the journey was changed in the meantime; reload it")
	case errors.Is(err, journeys.ErrStageVersion):
		return huma.Error412PreconditionFailed("the stage was changed in the meantime; reload the journey")
	case errors.Is(err, journeys.ErrHasRoute):
		return huma.Error409Conflict("this stage already has a route")
	case errors.Is(err, journeys.ErrBadOrder):
		return huma.Error422UnprocessableEntity(err.Error())
	case errors.Is(err, journeys.ErrNotYours):
		return huma.Error404NotFound("route not found")
	case errors.Is(err, routes.ErrInvalid):
		return huma.Error422UnprocessableEntity(err.Error())
	}
	return err
}
