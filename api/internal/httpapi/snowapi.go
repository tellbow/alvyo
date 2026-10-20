package httpapi

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/danielgtaylor/huma/v2"

	"github.com/tellbow/alvyo/api/internal/snow"
	"github.com/tellbow/alvyo/swiss/geo"
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

type snowAlongOutput struct {
	Body snow.Along
}

type lineSnowInput struct {
	Body struct {
		Line [][2]float64 `json:"line" minItems:"2" maxItems:"50000" doc:"[lon, lat] per point"`
	}
}

// snowAlong is the snow on line; too long a line is refused.
func snowAlong(ctx context.Context, d Deps, line []geo.Point) (snow.Along, error) {
	if geo.CumulativeDistance(line)[len(line)-1] > snow.MaxLineM {
		return snow.Along{}, huma.Error422UnprocessableEntity("line: too long")
	}
	return d.Snow.Along(ctx, line)
}

func registerSnow(api huma.API, d Deps) {
	tags := []string{"weather"}
	const alongDoc = "Where a line runs over snow (from 50 %; under 100 m nothing), how much of it on terrain steeper than 30°, and patches elsewhere, from the newest day of the snow cover."
	points := func(line [][3]float64) []geo.Point {
		pts := make([]geo.Point, len(line))
		for i, c := range line {
			pts[i] = geo.Point{Lon: c[0], Lat: c[1]}
		}
		return pts
	}

	huma.Register(api, huma.Operation{
		OperationID: "line-snow", Method: http.MethodPost, Path: "/routing/snow",
		Summary: "Snow along a line", Description: alongDoc, Tags: tags,
	}, func(ctx context.Context, in *lineSnowInput) (*snowAlongOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if !d.Limits.LegUser.Allow(u.ID.String()) {
			return nil, errTooMany
		}
		line := make([]geo.Point, len(in.Body.Line))
		for i, c := range in.Body.Line {
			line[i] = geo.Point{Lon: c[0], Lat: c[1]}
		}
		out := &snowAlongOutput{}
		out.Body, err = snowAlong(ctx, d, line)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "route-snow", Method: http.MethodGet, Path: "/routes/{id}/snow",
		Summary: "Snow along a route", Description: alongDoc, Tags: tags,
	}, func(ctx context.Context, in *routeIDInput) (*snowAlongOutput, error) {
		r, _, err := loadRoute(ctx, d, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		out := &snowAlongOutput{}
		if line := r.Line(); len(line) >= 2 {
			out.Body, err = snowAlong(ctx, d, points(line))
		} else {
			out.Body, err = d.Snow.Along(ctx, nil) // the day and credit only
		}
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "journey-snow", Method: http.MethodGet, Path: "/journeys/{id}/snow",
		Summary:     "Snow along a journey's stages",
		Description: alongDoc + " Stretches name their stage and are measured from its start.",
		Tags:        tags,
	}, func(ctx context.Context, in *journeyIDInput) (*snowAlongOutput, error) {
		j, _, err := loadJourney(ctx, d, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		out := &snowAlongOutput{}
		if out.Body, err = d.Snow.Along(ctx, nil); err != nil { // the day and credit
			return nil, err
		}
		for i, st := range j.StageList {
			if st.Route == nil || len(st.FullLine()) < 2 {
				continue
			}
			a, err := snowAlong(ctx, d, points(st.FullLine()))
			if err != nil {
				return nil, err
			}
			b := &out.Body
			b.SnowM += a.SnowM
			b.SteepM += a.SteepM
			b.PatchesM += a.PatchesM
			for _, s := range a.Stretches {
				s.Stage = i + 1
				b.Stretches = append(b.Stretches, s)
			}
		}
		return out, nil
	})

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
