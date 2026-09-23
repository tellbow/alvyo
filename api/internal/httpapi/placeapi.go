package httpapi

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"

	"github.com/tellbow/odysgeh/api/internal/places"
)

type nearbyPlacesInput struct {
	Lon   float64  `query:"lon" required:"true" minimum:"5.9" maximum:"10.6"`
	Lat   float64  `query:"lat" required:"true" minimum:"45.8" maximum:"47.9"`
	Q     string   `query:"q" maxLength:"60" doc:"Part of the name; widens the search to 30 km"`
	Kind  []string `query:"kind" enum:"pt_stop,hut,hotel,campsite" doc:"Comma-separated; all kinds if omitted"`
	Limit int      `query:"limit" minimum:"1" maximum:"30" default:"15"`
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
}
