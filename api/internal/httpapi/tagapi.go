package httpapi

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"

	"github.com/tellbow/alvyo/api/internal/tags"
)

type tagCountsOutput struct {
	Body struct {
		Tags []tags.Count `json:"tags"`
	}
}

// normalizeTags cleans submitted tags or refuses them with 422.
func normalizeTags(in []string) ([]string, error) {
	out, err := tags.Normalize(in)
	if err != nil {
		return nil, huma.Error422UnprocessableEntity(err.Error())
	}
	return out, nil
}

func registerTags(api huma.API, d Deps) {
	store := &tags.Store{DB: d.DB}

	huma.Register(api, huma.Operation{
		OperationID: "list-my-tags", Method: http.MethodGet, Path: "/me/tags",
		Summary:     "The tags on the logged-in user's routes, journeys and collections",
		Description: "With how often each is used, most used first; for suggestions and filters.",
		Tags:        []string{"tags"},
	}, func(ctx context.Context, _ *struct{}) (*tagCountsOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		out := &tagCountsOutput{}
		out.Body.Tags, err = store.Counts(ctx, u.ID)
		return out, err
	})
}
