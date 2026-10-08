package httpapi

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/auth"
)

// oidcCookie binds a sign-in to the browser that started it.
const oidcCookie = "alvyo_oidc"

type providersOutput struct {
	Body struct {
		Providers []providerInfo `json:"providers"`
	}
}

type providerInfo struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type oidcStartInput struct {
	Provider string `path:"provider"`
	Redirect string `query:"redirect" doc:"Local path to return to"`
	Link     bool   `query:"link" doc:"Connect the provider to the logged-in account instead of logging in"`
}

type oidcCallbackInput struct {
	Provider  string `path:"provider"`
	Code      string `query:"code"`
	State     string `query:"state"`
	Error     string `query:"error"`
	Cookie    string `cookie:"alvyo_oidc"`
	UserAgent string `header:"User-Agent"`
	Locale    string `cookie:"PARAGLIDE_LOCALE"`
}

type redirectOutput struct {
	Status    int
	Location  string        `header:"Location"`
	SetCookie []http.Cookie `header:"Set-Cookie"`
}

type identitiesOutput struct {
	Body struct {
		Identities []auth.IdentityInfo `json:"identities"`
	}
}

type providerInput struct {
	Provider string `path:"provider"`
}

// localPath keeps redirects on our site.
func localPath(p string) string {
	if !strings.HasPrefix(p, "/") || strings.HasPrefix(p, "//") || strings.ContainsAny(p, "\\\r\n") {
		return "/"
	}
	return p
}

func registerOIDC(api huma.API, d Deps) {
	tags := []string{"auth"}
	if d.OIDC == nil {
		d.OIDC = &auth.OIDC{} // no providers: start answers 404
	}
	cookie := func(value string, maxAge int) http.Cookie {
		return http.Cookie{Name: oidcCookie, Value: value, Path: "/api/v1/auth/oidc", MaxAge: maxAge,
			HttpOnly: true, Secure: d.secureCookies(), SameSite: http.SameSiteLaxMode}
	}
	// back sends the browser to a page of the web app, with an outcome
	// the page shows (?oidc=…).
	back := func(path, outcome string, cookies ...http.Cookie) *redirectOutput {
		if outcome != "" {
			sep := "?"
			if strings.Contains(path, "?") {
				sep = "&"
			}
			path += sep + "oidc=" + url.QueryEscape(outcome)
		}
		return &redirectOutput{Status: http.StatusFound, Location: d.PublicURL + path,
			SetCookie: append(cookies, cookie("", -1))}
	}

	huma.Register(api, huma.Operation{
		OperationID: "list-providers", Method: http.MethodGet, Path: "/auth/providers",
		Summary: "Configured sign-in providers", Tags: tags,
	}, func(_ context.Context, _ *struct{}) (*providersOutput, error) {
		out := &providersOutput{}
		out.Body.Providers = []providerInfo{}
		for _, p := range d.OIDC.Providers {
			out.Body.Providers = append(out.Body.Providers, providerInfo{ID: p.ID, Name: p.Name})
		}
		return out, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "start-oidc", Method: http.MethodGet, Path: "/auth/oidc/{provider}/start",
		Summary:     "Go to a provider to log in, sign up or connect it",
		Description: "Redirects to the provider, which returns to /auth/oidc/{provider}/callback.",
		Tags:        tags,
	}, func(ctx context.Context, in *oidcStartInput) (*redirectOutput, error) {
		redirect := localPath(in.Redirect)
		link := uuid.Nil
		if in.Link {
			u, err := requireUser(ctx)
			if err != nil {
				return back("/login?redirect=%2Faccount", ""), nil
			}
			// Only the address's owner, just logged in: a provider stays
			// connected through password resets and ended sessions, so it
			// must not come from whoever signed up with someone else's
			// address, or from a session left open.
			if u.EmailVerifiedAt == nil {
				return back("/account", "verify"), nil
			}
			if d.Auth.RecentLogin(ctx, u, sessionToken(ctx)) != nil {
				return back("/account", "again"), nil
			}
			link, redirect = u.ID, "/account"
		}
		to, state, err := d.OIDC.Start(ctx, in.Provider, redirect, link)
		if errors.Is(err, auth.ErrUnknownProvider) {
			return nil, huma.Error404NotFound("no such provider")
		}
		if errors.Is(err, auth.ErrOIDCBusy) {
			return back(redirect, "busy"), nil
		}
		if err != nil {
			slog.ErrorContext(ctx, "oidc start", "provider", in.Provider, "err", err)
			return back(redirect, "unavailable"), nil
		}
		return &redirectOutput{Status: http.StatusFound, Location: to,
			SetCookie: []http.Cookie{cookie(state, int((10 * time.Minute).Seconds()))}}, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "oidc-callback", Method: http.MethodGet, Path: "/auth/oidc/{provider}/callback",
		Summary:     "Where providers send the browser back",
		Description: "Logs in, creates an account or connects the provider, then redirects to the web app with ?oidc=<outcome> on problems.",
		Tags:        tags,
	}, func(ctx context.Context, in *oidcCallbackInput) (*redirectOutput, error) {
		if in.Error != "" {
			return back("/login", "cancelled"), nil
		}
		id, redirect, link, err := d.OIDC.Finish(ctx, in.Provider, in.State, in.Cookie, in.Code)
		if err != nil {
			slog.InfoContext(ctx, "oidc callback", "provider", in.Provider, "err", err)
			return back("/login", "failed"), nil
		}
		if link != uuid.Nil {
			switch err := d.Auth.LinkIdentity(ctx, link, id); {
			case errors.Is(err, auth.ErrIdentityTaken):
				return back("/account", "taken"), nil
			case errors.Is(err, auth.ErrProviderLinked):
				return back("/account", "already"), nil
			case err != nil:
				return nil, err
			}
			return back("/account", "linked"), nil
		}
		locale := in.Locale
		if locale != "de" && locale != "en" && locale != "fr" && locale != "it" {
			locale = "de"
		}
		allowNew := func() bool { return d.Limits.SignupIP.Allow(limitKey(ctx)) }
		u, s, err := d.Auth.IdentityLogin(ctx, id, locale, in.UserAgent, allowNew)
		switch {
		case errors.Is(err, auth.ErrSignupLimit):
			return back("/login", "busy"), nil
		case errors.Is(err, auth.ErrEmailTaken):
			return back("/login", "exists"), nil
		case errors.Is(err, auth.ErrNoEmail):
			return back("/login", "noemail"), nil
		case errors.Is(err, auth.ErrBanned):
			return back("/login", "banned"), nil
		case err != nil:
			return nil, err
		}
		slog.InfoContext(ctx, "oidc login", "provider", in.Provider, "user", u.ID)
		return back(redirect, "", newSessionCookie(s.Token, s.ExpiresAt, d.secureCookies())), nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "list-identities", Method: http.MethodGet, Path: "/me/identities",
		Summary: "Provider accounts connected to the account", Tags: []string{"me"},
	}, func(ctx context.Context, _ *struct{}) (*identitiesOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		out := &identitiesOutput{}
		out.Body.Identities, err = d.Auth.Identities(ctx, u.ID)
		return out, err
	})

	huma.Register(api, huma.Operation{
		OperationID: "unlink-identity", Method: http.MethodDelete, Path: "/me/identities/{provider}",
		Summary: "Disconnect a provider (not the last way to log in)", Tags: []string{"me"},
	}, func(ctx context.Context, in *providerInput) (*identitiesOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		switch err := d.Auth.UnlinkIdentity(ctx, u, in.Provider); {
		case errors.Is(err, auth.ErrUnknownProvider):
			return nil, huma.Error404NotFound("not connected to this provider")
		case errors.Is(err, auth.ErrLastLogin):
			return nil, huma.Error409Conflict("this is your last way to log in; set a password or add a passkey first")
		case err != nil:
			return nil, err
		}
		out := &identitiesOutput{}
		out.Body.Identities, err = d.Auth.Identities(ctx, u.ID)
		return out, err
	})
}
