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

// oidcPostInput is a provider's answer posted back (Apple: form_post):
// code, state, error and, on the first sign-in, user.
type oidcPostInput struct {
	Provider  string `path:"provider"`
	Cookie    string `cookie:"alvyo_oidc"`
	UserAgent string `header:"User-Agent"`
	Locale    string `cookie:"PARAGLIDE_LOCALE"`
	RawBody   []byte `contentType:"application/x-www-form-urlencoded"`
}

type nativeSignInInput struct {
	Provider  string `path:"provider"`
	UserAgent string `header:"User-Agent"`
	Body      struct {
		IdentityToken     string `json:"identity_token" maxLength:"8000"`
		AuthorizationCode string `json:"authorization_code" maxLength:"1000"`
		Nonce             string `json:"nonce" maxLength:"200" doc:"The raw nonce whose SHA-256 (hex) the app asked for"`
		Name              string `json:"name,omitempty" maxLength:"200" doc:"The name Apple gave the app on the first sign-in"`
		Locale            string `json:"locale,omitempty" enum:"de,en,fr,it"`
	}
}

type appleNotificationInput struct {
	Body struct {
		Payload string `json:"payload" maxLength:"20000"`
	}
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
		// Apple posts its answer from its own site: a Lax cookie would stay
		// behind. Without HTTPS (local development) browsers refuse None.
		same := http.SameSiteNoneMode
		if !d.secureCookies() {
			same = http.SameSiteLaxMode
		}
		return http.Cookie{Name: oidcCookie, Value: value, Path: "/api/v1/auth/oidc", MaxAge: maxAge,
			HttpOnly: true, Secure: d.secureCookies(), SameSite: same}
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

	// callback finishes a sign-in from the provider's answer: user is the
	// JSON Apple posts on the first sign-in.
	callback := func(ctx context.Context, in *oidcCallbackInput, user string) (*redirectOutput, error) {
		if in.Error != "" {
			return back("/login", "cancelled"), nil
		}
		id, redirect, link, err := d.OIDC.Finish(ctx, in.Provider, in.State, in.Cookie, in.Code, user)
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
	}

	huma.Register(api, huma.Operation{
		OperationID: "oidc-callback", Method: http.MethodGet, Path: "/auth/oidc/{provider}/callback",
		Summary:     "Where providers send the browser back",
		Description: "Logs in, creates an account or connects the provider, then redirects to the web app with ?oidc=<outcome> on problems.",
		Tags:        tags,
	}, func(ctx context.Context, in *oidcCallbackInput) (*redirectOutput, error) {
		return callback(ctx, in, "")
	})

	huma.Register(api, huma.Operation{
		OperationID: "oidc-callback-post", Method: http.MethodPost, Path: "/auth/oidc/{provider}/callback",
		Summary:     "Where providers post their answer back (Apple)",
		Description: "As the GET callback, for providers that post code and state as a form (response_mode=form_post).",
		Tags:        tags,
	}, func(ctx context.Context, in *oidcPostInput) (*redirectOutput, error) {
		f, err := url.ParseQuery(string(in.RawBody))
		if err != nil {
			return nil, huma.Error400BadRequest("not a form")
		}
		return callback(ctx, &oidcCallbackInput{Provider: in.Provider, Code: f.Get("code"), State: f.Get("state"),
			Error: f.Get("error"), Cookie: in.Cookie, UserAgent: in.UserAgent, Locale: in.Locale}, f.Get("user"))
	})

	huma.Register(api, huma.Operation{
		OperationID: "native-sign-in", Method: http.MethodPost, Path: "/auth/oidc/{provider}/native",
		Summary:     "Log in or sign up with the iOS app's own Apple sign-in",
		Description: "Checks the identity token (for the app, with the nonce) and redeems the authorization code. An address that already has an account answers 409: its owner connects Apple on the website first.",
		Tags:        tags,
	}, func(ctx context.Context, in *nativeSignInInput) (*sessionOutput, error) {
		id, err := d.OIDC.AppleNative(ctx, in.Provider, in.Body.IdentityToken, in.Body.AuthorizationCode,
			in.Body.Nonce, in.Body.Name)
		switch {
		case errors.Is(err, auth.ErrUnknownProvider):
			return nil, huma.Error404NotFound("no such provider")
		case err != nil:
			slog.InfoContext(ctx, "native sign-in", "provider", in.Provider, "err", err)
			return nil, huma.Error401Unauthorized("the provider's answer was not accepted")
		}
		locale := in.Body.Locale
		if locale == "" {
			locale = "de"
		}
		allowNew := func() bool { return d.Limits.SignupIP.Allow(limitKey(ctx)) }
		u, s, err := d.Auth.IdentityLogin(ctx, id, locale, in.UserAgent, allowNew)
		switch {
		case errors.Is(err, auth.ErrSignupLimit):
			return nil, errTooMany
		case errors.Is(err, auth.ErrEmailTaken):
			return nil, huma.Error409Conflict("an account has this e-mail address; connect the provider on the website first")
		case errors.Is(err, auth.ErrNoEmail):
			return nil, huma.Error422UnprocessableEntity("the provider gave no e-mail address")
		case errors.Is(err, auth.ErrBanned):
			return nil, huma.Error403Forbidden("account banned")
		case err != nil:
			return nil, err
		}
		slog.InfoContext(ctx, "native login", "provider", in.Provider, "user", u.ID)
		return d.sessionResponse(u, s), nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "apple-notification", Method: http.MethodPost, Path: "/auth/apple/notifications",
		Summary:     "Apple's server-to-server notifications",
		Description: "Apple tells when someone stops using Sign in with Apple with Alvyo or deletes their Apple account: the identity is removed.",
		Tags:        tags, DefaultStatus: http.StatusOK,
	}, func(ctx context.Context, in *appleNotificationInput) (*struct{}, error) {
		ev, err := d.OIDC.AppleEvent(ctx, in.Body.Payload)
		if errors.Is(err, auth.ErrUnknownProvider) {
			return nil, huma.Error404NotFound("sign in with Apple is not set up")
		}
		if err != nil {
			slog.InfoContext(ctx, "apple notification", "err", err)
			return nil, huma.Error400BadRequest("not a notification from Apple")
		}
		slog.InfoContext(ctx, "apple notification", "type", ev.Type)
		switch ev.Type {
		case "consent-revoked", "account-delete":
			return nil, d.Auth.DropIdentity(ctx, ev.Provider, ev.Subject)
		}
		// email-disabled and email-enabled: Apple's relay drops or forwards
		// our mail itself.
		return nil, nil
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
			return nil, huma.Error409Conflict("this is your last way to log in; set a password first")
		case err != nil:
			return nil, err
		}
		out := &identitiesOutput{}
		out.Body.Identities, err = d.Auth.Identities(ctx, u.ID)
		return out, err
	})
}
