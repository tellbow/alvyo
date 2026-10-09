package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/auth"
)

type accessTokensOutput struct {
	Body struct {
		Tokens []auth.AccessToken `json:"tokens"`
	}
}

type createAccessTokenInput struct {
	Body struct {
		Name string `json:"name" minLength:"1" maxLength:"60" doc:"What it is for, e.g. «Claude Desktop»"`
	}
}

type createAccessTokenOutput struct {
	Body struct {
		auth.AccessToken
		Token string `json:"token" doc:"The token itself, shown only now: Authorization: Bearer alvyo_pat_…"`
	}
}

type accessTokenIDInput struct {
	ID string `path:"id" format:"uuid"`
}

// registerAccessTokens: personal access tokens for AI assistants (the MCP
// endpoint) and the CLI. They only read (withAccessToken).
func registerAccessTokens(api huma.API, d Deps) {
	tags := []string{"me"}

	huma.Register(api, huma.Operation{
		OperationID: "list-access-tokens", Method: http.MethodGet, Path: "/me/tokens",
		Summary: "My personal access tokens, the newest first", Tags: tags,
	}, func(ctx context.Context, _ *struct{}) (*accessTokensOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		out := &accessTokensOutput{}
		out.Body.Tokens, err = d.Auth.AccessTokens(ctx, u.ID)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "create-access-token", Method: http.MethodPost, Path: "/me/tokens",
		Summary:     "Create a personal access token",
		Description: "It reads what the account may see, through the API's GET operations and the MCP endpoint (`/api/v1/mcp`); it cannot change anything. At most 20 per account.",
		Tags:        tags, DefaultStatus: http.StatusCreated,
	}, func(ctx context.Context, in *createAccessTokenInput) (*createAccessTokenOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if !d.Limits.NewAccessToken.Allow(u.ID.String()) {
			return nil, errTooMany
		}
		name := strings.TrimSpace(in.Body.Name)
		if name == "" {
			return nil, huma.Error422UnprocessableEntity("name is empty")
		}
		t, token, err := d.Auth.CreateAccessToken(ctx, u.ID, name)
		if errors.Is(err, auth.ErrTooManyTokens) {
			return nil, huma.Error422UnprocessableEntity("at most 20 access tokens")
		}
		if err != nil {
			return nil, err
		}
		out := &createAccessTokenOutput{}
		out.Body.AccessToken, out.Body.Token = t, token
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "revoke-access-token", Method: http.MethodDelete, Path: "/me/tokens/{id}",
		Summary: "Revoke a personal access token; it stops working at once", Tags: tags,
		DefaultStatus: http.StatusNoContent,
	}, func(ctx context.Context, in *accessTokenIDInput) (*struct{}, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		err = d.Auth.RevokeAccessToken(ctx, u.ID, uuid.MustParse(in.ID))
		if errors.Is(err, auth.ErrNoAccessToken) {
			return nil, huma.Error404NotFound("access token not found")
		}
		return nil, err
	})
}
