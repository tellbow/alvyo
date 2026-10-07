package httpapi

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/danielgtaylor/huma/v2"

	"github.com/tellbow/alvyo/api/internal/precip"
)

type precipFrame struct {
	precip.Frame
	URL string `json:"url" doc:"The picture (PNG, Web Mercator, transparent where dry)"`
}

type precipOutput struct {
	CacheControl string `header:"Cache-Control"`
	Body         struct {
		Bounds      precip.Bounds  `json:"bounds"`
		Frames      []precipFrame  `json:"frames" doc:"Oldest first: the radar's last hour, then the forecast; empty while there are none"`
		Legend      []precip.Level `json:"legend"`
		Attribution string         `json:"attribution"`
	}
}

type precipImageInput struct {
	Kind string `path:"kind" enum:"radar,forecast"`
	Time int64  `path:"time" doc:"Unix seconds of the frame's time"`
	V    int64  `query:"v" doc:"Version; changes when the picture does"`
}

func registerPrecip(api huma.API, d Deps) {
	tags := []string{"weather"}

	huma.Register(api, huma.Operation{
		OperationID: "get-precipitation",
		Method:      http.MethodGet,
		Path:        "/weather/precip",
		Summary:     "Rain on the map: the radar's last hour and the forecast",
		Description: "MeteoSwiss's radar every 5 minutes and the ICON-CH1 forecast hourly, as pictures over bounds.",
		Tags:        tags,
	}, func(ctx context.Context, _ *struct{}) (*precipOutput, error) {
		frames, bounds, err := d.Precip.Timeline(ctx, time.Now())
		if err != nil {
			return nil, err
		}
		out := &precipOutput{CacheControl: "public, max-age=60"}
		out.Body.Bounds, out.Body.Legend, out.Body.Attribution = bounds, precip.Legend, "MeteoSchweiz"
		out.Body.Frames = []precipFrame{}
		for _, f := range frames {
			out.Body.Frames = append(out.Body.Frames, precipFrame{f,
				fmt.Sprintf("/api/v1/weather/precip/%s/%d/frame.png?v=%d", f.Kind, f.Time.Unix(), f.Version)})
		}
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-precipitation-image",
		Method:      http.MethodGet,
		Path:        "/weather/precip/{kind}/{time}/frame.png",
		Summary:     "One picture of the rain on the map",
		Tags:        tags,
	}, func(ctx context.Context, in *precipImageInput) (*imageOutput, error) {
		b, err := d.Precip.PNG(ctx, in.Kind, time.Unix(in.Time, 0))
		if errors.Is(err, precip.ErrNotFound) {
			return nil, huma.Error404NotFound("picture not found")
		}
		if err != nil {
			return nil, err
		}
		// A new picture for the same time comes with another version.
		return &imageOutput{ContentType: "image/png", CacheControl: "public, max-age=86400, immutable", Body: b}, nil
	})
}
