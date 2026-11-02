package httpapi

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
)

// SpamProof goes along with every open form (see the spam package).
type SpamProof struct {
	Challenge string `json:"challenge,omitempty" maxLength:"200" doc:"From POST /challenge"`
	Nonce     string `json:"nonce,omitempty" maxLength:"20" doc:"A number so that the SHA-256 of «challenge:nonce» starts with the challenge's zero bits"`
	Website   string `json:"website,omitempty" doc:"Leave empty (spam trap)"`
}

type challengeOutput struct {
	Body struct {
		Challenge string `json:"challenge"`
		Bits      int    `json:"bits" doc:"Leading zero bits of the SHA-256 of «challenge:nonce»"`
		WaitMs    int64  `json:"wait_ms" doc:"An answer sooner than this is refused"`
	}
}

func registerSpam(api huma.API, d Deps) {
	huma.Register(api, huma.Operation{
		OperationID: "new-challenge", Method: http.MethodPost, Path: "/challenge",
		Summary:     "A challenge for an open form",
		Description: "Signup, comments, reports and bug reports need one, answered: a small proof-of-work and a minimum time to fill the form. Valid for 30 minutes, once.",
		Tags:        []string{"auth"},
	}, func(context.Context, *struct{}) (*challengeOutput, error) {
		out := &challengeOutput{}
		out.Body.Challenge, out.Body.Bits, out.Body.WaitMs = d.Spam.Challenge(), d.Spam.Bits, d.Spam.Wait.Milliseconds()
		return out, nil
	})
}

// checkProof refuses what a bot gives away; before the limiters, which are for
// people and should not count this.
func (d Deps) checkProof(p SpamProof) error {
	if p.Website != "" {
		return huma.Error400BadRequest("invalid request")
	}
	if !d.Spam.Check(p.Challenge, p.Nonce) {
		return huma.Error422UnprocessableEntity("challenge not answered",
			&huma.ErrorDetail{Location: "body.challenge", Message: "not answered"})
	}
	return nil
}
