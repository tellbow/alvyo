package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/danielgtaylor/huma/v2"
	"github.com/go-webauthn/webauthn/protocol"

	"github.com/tellbow/alvyo/api/internal/auth"
)

type passkeyRegisterBeginInput struct {
	Body struct {
		Password string `json:"password,omitempty" maxLength:"128" doc:"Current password, as confirmation; accounts without one must have logged in within 15 minutes"`
	}
}

type passkeyRegisterBeginOutput struct {
	Body struct {
		Ceremony string                                      `json:"ceremony" doc:"Pass back with the answer"`
		Options  protocol.PublicKeyCredentialCreationOptions `json:"options" doc:"For navigator.credentials.create (publicKey)"`
	}
}

type passkeyRegisterFinishInput struct {
	Body struct {
		Ceremony string          `json:"ceremony"`
		Name     string          `json:"name" minLength:"1" maxLength:"60" doc:"To recognise it later, e.g. the device"`
		Response json.RawMessage `json:"response" doc:"The PublicKeyCredential as JSON (toJSON())"`
	}
}

type passkeyLoginBeginOutput struct {
	Body struct {
		Ceremony string                                     `json:"ceremony"`
		Options  protocol.PublicKeyCredentialRequestOptions `json:"options" doc:"For navigator.credentials.get (publicKey)"`
	}
}

type passkeyLoginFinishInput struct {
	UserAgent string `header:"User-Agent"`
	Body      struct {
		Ceremony string          `json:"ceremony"`
		Response json.RawMessage `json:"response"`
	}
}

type passkeysOutput struct {
	Body struct {
		Passkeys []auth.PasskeyInfo `json:"passkeys"`
	}
}

type passkeyIDInput struct {
	ID string `path:"id" maxLength:"1400"`
}

func passkeyError(err error) error {
	switch {
	case errors.Is(err, auth.ErrCeremony):
		return huma.Error409Conflict("the passkey request expired; start again")
	case errors.Is(err, auth.ErrPasskeyMissing):
		return huma.Error404NotFound("passkey not found")
	case errors.Is(err, auth.ErrLastLogin):
		return huma.Error409Conflict("this is your last way to log in; add another first")
	case errors.Is(err, auth.ErrBanned):
		return huma.Error403Forbidden("account banned")
	case errors.Is(err, auth.ErrPasskey):
		return huma.Error422UnprocessableEntity("the passkey was not accepted")
	}
	return err
}

func registerPasskeys(api huma.API, d Deps) {
	tags := []string{"auth"}
	off := func() error {
		if d.Auth == nil || d.Auth.WebAuthn == nil {
			return huma.Error503ServiceUnavailable("passkeys are not set up")
		}
		return nil
	}

	huma.Register(api, huma.Operation{
		OperationID: "begin-passkey-registration", Method: http.MethodPost, Path: "/me/passkeys/begin",
		Summary: "Start adding a passkey to the account", Tags: tags,
	}, func(ctx context.Context, in *passkeyRegisterBeginInput) (*passkeyRegisterBeginOutput, error) {
		if err := off(); err != nil {
			return nil, err
		}
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if !d.Limits.LoginAccount.Allow(u.Username) {
			return nil, errTooMany
		}
		// A passkey outlasts password resets: only for the address's owner.
		if u.EmailVerifiedAt == nil {
			return nil, huma.Error403Forbidden("confirm your e-mail address first")
		}
		if err := d.Auth.Confirm(ctx, u, in.Body.Password, sessionToken(ctx)); err != nil {
			return nil, confirmError(err)
		}
		out := &passkeyRegisterBeginOutput{}
		if out.Body.Options, out.Body.Ceremony, err = d.Auth.BeginPasskeyRegistration(ctx, u); err != nil {
			return nil, passkeyError(err)
		}
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "finish-passkey-registration", Method: http.MethodPost, Path: "/me/passkeys",
		Summary: "Store the passkey the browser created", Tags: tags,
	}, func(ctx context.Context, in *passkeyRegisterFinishInput) (*passkeysOutput, error) {
		if err := off(); err != nil {
			return nil, err
		}
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		name := strings.TrimSpace(in.Body.Name)
		if err := d.Auth.FinishPasskeyRegistration(ctx, u, in.Body.Ceremony, name, in.Body.Response); err != nil {
			return nil, passkeyError(err)
		}
		out := &passkeysOutput{}
		out.Body.Passkeys, err = d.Auth.Passkeys(ctx, u.ID)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "list-passkeys", Method: http.MethodGet, Path: "/me/passkeys",
		Summary: "The account's passkeys", Tags: tags,
	}, func(ctx context.Context, _ *struct{}) (*passkeysOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		out := &passkeysOutput{}
		out.Body.Passkeys, err = d.Auth.Passkeys(ctx, u.ID)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "delete-passkey", Method: http.MethodDelete, Path: "/me/passkeys/{id}",
		Summary: "Remove a passkey (not the last way to log in)", Tags: tags,
	}, func(ctx context.Context, in *passkeyIDInput) (*passkeysOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if err := d.Auth.DeletePasskey(ctx, u, in.ID); err != nil {
			return nil, passkeyError(err)
		}
		out := &passkeysOutput{}
		out.Body.Passkeys, err = d.Auth.Passkeys(ctx, u.ID)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "begin-passkey-login", Method: http.MethodPost, Path: "/auth/passkey/begin",
		Summary: "Start logging in with a passkey", Tags: tags,
	}, func(ctx context.Context, _ *struct{}) (*passkeyLoginBeginOutput, error) {
		if err := off(); err != nil {
			return nil, err
		}
		if !d.Limits.LoginIP.Allow(clientIP(ctx)) {
			return nil, errTooMany
		}
		out := &passkeyLoginBeginOutput{}
		var err error
		if out.Body.Options, out.Body.Ceremony, err = d.Auth.BeginPasskeyLogin(); err != nil {
			return nil, err
		}
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "finish-passkey-login", Method: http.MethodPost, Path: "/auth/passkey",
		Summary: "Log in with the passkey the browser chose", Tags: tags,
	}, func(ctx context.Context, in *passkeyLoginFinishInput) (*sessionOutput, error) {
		if err := off(); err != nil {
			return nil, err
		}
		u, s, err := d.Auth.FinishPasskeyLogin(ctx, in.Body.Ceremony, in.Body.Response, in.UserAgent)
		if err != nil {
			return nil, passkeyError(err)
		}
		return d.sessionResponse(u, s), nil
	})
}
