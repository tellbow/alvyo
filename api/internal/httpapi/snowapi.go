package httpapi

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/danielgtaylor/huma/v2"

	"github.com/tellbow/alvyo/api/internal/snow"
)

type snowOutput struct {
	CacheControl string `header:"Cache-Control"`
	Body         struct {
		Date        string       `json:"date,omitempty" doc:"The day the snow cover is for (YYYY-MM-DD); missing while there is none"`
		Tiles       string       `json:"tiles,omitempty" doc:"The tiles' URL ({z}, {x}, {y}): PNG, Web Mercator, transparent without snow"`
		MinZoom     int          `json:"minzoom"`
		MaxZoom     int          `json:"maxzoom"`
		Bounds      snow.Extent  `json:"bounds"`
		Legend      []snow.Class `json:"legend"`
		Attribution string       `json:"attribution"`
	}
}

type snowTileInput struct {
	Day string `path:"day" format:"date" doc:"YYYY-MM-DD"`
	Z   int    `path:"z" minimum:"0" maximum:"20"`
	X   int    `path:"x" minimum:"0"`
	Y   int    `path:"y" minimum:"0"`
}

type snowTileOutput struct {
	Status       int
	ContentType  string `header:"Content-Type"`
	CacheControl string `header:"Cache-Control"`
	Body         []byte
}

func registerSnow(api huma.API, d Deps) {
	tags := []string{"weather"}

	huma.Register(api, huma.Operation{
		OperationID: "get-snow-cover",
		Method:      http.MethodGet,
		Path:        "/weather/snow",
		Summary:     "Snow cover on the map",
		Description: "The Copernicus Land Monitoring Service's daily snow cover (60 m; in cloudy weather up to 7 days old) as map tiles over bounds.",
		Tags:        tags,
	}, func(ctx context.Context, _ *struct{}) (*snowOutput, error) {
		day, ok, err := d.Snow.Latest(ctx)
		if err != nil {
			return nil, err
		}
		out := &snowOutput{CacheControl: "public, max-age=600"}
		b := &out.Body
		b.MinZoom, b.MaxZoom, b.Bounds, b.Legend, b.Attribution = snow.MinZoom, snow.MaxZoom, snow.Area, snow.Legend, snow.Attribution
		if ok {
			b.Date = day.Format(time.DateOnly)
			b.Tiles = "/api/v1/weather/snow/" + b.Date + "/{z}/{x}/{y}/tile.png"
		}
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-snow-tile",
		Method:      http.MethodGet,
		Path:        "/weather/snow/{day}/{z}/{x}/{y}/tile.png",
		Summary:     "One tile of the snow cover",
		Description: "204 where there is no snow; 404 for a day that is not (or no longer) there.",
		Tags:        tags,
	}, func(ctx context.Context, in *snowTileInput) (*snowTileOutput, error) {
		day, err := time.Parse(time.DateOnly, in.Day)
		if err != nil {
			return nil, huma.Error422UnprocessableEntity("day: YYYY-MM-DD")
		}
		png, err := d.Snow.Tile(ctx, day, in.Z, in.X, in.Y)
		if errors.Is(err, snow.ErrNotFound) {
			return nil, huma.Error404NotFound("no snow cover for this day")
		}
		if err != nil {
			return nil, err
		}
		// A day's tiles never change.
		out := &snowTileOutput{Status: http.StatusOK, ContentType: "image/png",
			CacheControl: "public, max-age=86400, immutable", Body: png}
		if png == nil {
			out.Status, out.ContentType = http.StatusNoContent, ""
		}
		return out, nil
	})
}
