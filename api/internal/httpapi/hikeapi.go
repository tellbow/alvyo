package httpapi

import (
	"context"
	"log/slog"
	"net/http"
	"time"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/imports"
	"github.com/tellbow/alvyo/swiss/geo"
)

type hikePoint struct {
	Lon  float64   `json:"lon"`
	Lat  float64   `json:"lat"`
	Time time.Time `json:"t"`
}

type uploadHikeInput struct {
	Body struct {
		ID      string      `json:"id" minLength:"1" maxLength:"100" doc:"The app's id of the recording: uploading it again returns the route made the first time"`
		RouteID string      `json:"route_id,omitempty" required:"false" doc:"The planned route that was followed"`
		Title   string      `json:"title" minLength:"1" maxLength:"120"`
		Points  []hikePoint `json:"points" minItems:"2" maxItems:"50000" doc:"In the order recorded"`
	}
}

type uploadHikeOutput struct {
	Status int
	Body   struct {
		ID string `json:"id" format:"uuid"`
	}
}

// recorded is the route source of hikes recorded with the app.
const recorded = "recorded"

func registerHikes(api huma.API, d Deps) {
	huma.Register(api, huma.Operation{
		OperationID: "upload-hike", Method: http.MethodPost, Path: "/hikes",
		MaxBodyBytes: 8 << 20, // 50,000 points; the default 1 MB is a five-hour Watch hike
		Summary:      "Save a hike recorded with the app as a private route",
		Description: "The track gets elevation and trail data like an import, and the route knows when it was hiked, how long it took and the planned route. " +
			"201 for a new route, 200 when the recording was uploaded before; 503 when the elevation service is unavailable (upload again later).",
		Tags: []string{"routes"},
	}, func(ctx context.Context, in *uploadHikeInput) (*uploadHikeOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		// hike marks the route as hiked, also on an upload again: the first
		// may have saved the route and failed after it.
		hike := func(id string) error {
			b := in.Body
			// The planned route, if the hiker may (still) see it.
			var planned *uuid.UUID
			if b.RouteID != "" {
				if p, _, err := loadRoute(ctx, d, b.RouteID, ""); err == nil {
					id := uuid.MustParse(p.ID)
					planned = &id
				}
			}
			first, last := b.Points[0].Time, b.Points[len(b.Points)-1].Time
			return d.Routes.SetHike(ctx, uuid.MustParse(id), first, max(0, int(last.Sub(first).Seconds())), planned)
		}
		existing := func() (*uploadHikeOutput, error) {
			refs, err := d.Routes.ImportedRefs(ctx, u.ID, recorded)
			if err != nil || refs[in.Body.ID] == "" {
				return nil, err
			}
			if err := hike(refs[in.Body.ID]); err != nil {
				return nil, err
			}
			out := &uploadHikeOutput{Status: http.StatusOK}
			out.Body.ID = refs[in.Body.ID]
			return out, nil
		}
		if out, err := existing(); out != nil || err != nil {
			return out, err
		}
		if !d.Limits.Import.Allow(u.ID.String()) {
			return nil, errTooMany
		}

		b := in.Body
		t := imports.Track{Name: b.Title}
		for _, p := range b.Points {
			t.Points = append(t.Points, geo.Point{Lon: p.Lon, Lat: p.Lat})
		}
		r, err := d.Importer.Route(ctx, u.ID, t, imports.Source{Kind: recorded, Ref: b.ID})
		if err != nil {
			switch imports.Reason(err) {
			case "outside":
				return nil, huma.Error422UnprocessableEntity("the hike leaves Switzerland and Liechtenstein")
			case "short":
				return nil, huma.Error422UnprocessableEntity("the hike is too short")
			case "elevation":
				return nil, huma.Error503ServiceUnavailable("elevations are unavailable; upload again later")
			case "duplicate": // uploaded twice at the same time
				if out, err := existing(); out != nil || err != nil {
					return out, err
				}
			}
			slog.ErrorContext(ctx, "hike upload", "err", err)
			return nil, huma.Error500InternalServerError("the hike could not be saved")
		}

		if err := hike(r.ID); err != nil {
			return nil, err
		}
		out := &uploadHikeOutput{Status: http.StatusCreated}
		out.Body.ID = r.ID
		return out, nil
	})
}
