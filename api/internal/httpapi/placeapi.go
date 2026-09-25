package httpapi

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"

	"github.com/tellbow/alvyo/api/internal/places"
)

type nearbyPlacesInput struct {
	Lon   float64  `query:"lon" required:"true" minimum:"5.9" maximum:"10.6"`
	Lat   float64  `query:"lat" required:"true" minimum:"45.8" maximum:"47.9"`
	Q     string   `query:"q" maxLength:"60" doc:"Part of the name; widens the search to 30 km"`
	Kind  []string `query:"kind" enum:"pt_stop,hut,hotel,campsite" doc:"Comma-separated; all kinds if omitted"`
	Limit int      `query:"limit" minimum:"1" maximum:"30" default:"15"`
}

type searchPlacesInput struct {
	Q   string  `query:"q" required:"true" minLength:"2" maxLength:"80"`
	Lon float64 `query:"lon" minimum:"5.9" maximum:"10.6" default:"8.23" doc:"Map centre: among equally good matches, the nearest come first"`
	Lat float64 `query:"lat" minimum:"45.8" maximum:"47.9" default:"46.8"`
}

type searchPlacesOutput struct {
	Body struct {
		Places []places.Found `json:"places"`
	}
}

type nearbyPlacesOutput struct {
	Body struct {
		Places []places.Place `json:"places"`
	}
}

func registerPlaces(api huma.API, d Deps) {
	huma.Register(api, huma.Operation{
		OperationID: "nearby-places", Method: http.MethodGet, Path: "/places/nearby",
		Summary: "Stops, huts and accommodation near a point, nearest first", Tags: []string{"places"},
	}, func(ctx context.Context, in *nearbyPlacesInput) (*nearbyPlacesOutput, error) {
		ps, err := d.Places.Nearby(ctx, places.Query{Lon: in.Lon, Lat: in.Lat, Name: in.Q, Kinds: in.Kind, Limit: in.Limit})
		if err != nil {
			return nil, err
		}
		out := &nearbyPlacesOutput{}
		out.Body.Places = ps
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "search-places", Method: http.MethodGet, Path: "/places/search",
		Summary:     "Find places by name, for route planning",
		Description: "Our stops, huts and accommodation first, then swisstopo's geographical names (places, peaks, passes, lakes …); addresses when the text has a house number.",
		Tags:        []string{"places"},
	}, func(ctx context.Context, in *searchPlacesInput) (*searchPlacesOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if !d.Limits.Search.Allow(u.ID.String()) {
			return nil, errTooMany
		}
		fs, err := d.Places.Search(ctx, in.Q, [2]float64{in.Lon, in.Lat}, u.Locale)
		if err != nil {
			return nil, err
		}
		out := &searchPlacesOutput{}
		out.Body.Places = fs
		return out, nil
	})
}
