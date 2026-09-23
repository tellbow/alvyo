package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/danielgtaylor/huma/v2"

	"github.com/tellbow/odysgeh/api/internal/auth"
	"github.com/tellbow/odysgeh/api/internal/dbq"
	"github.com/tellbow/odysgeh/api/internal/ratelimit"
)

// Limits are the rate limits of the account endpoints.
type Limits struct {
	LoginIP      *ratelimit.Limiter
	LoginAccount *ratelimit.Limiter
	SignupIP     *ratelimit.Limiter
	ForgotIP     *ratelimit.Limiter
	ForgotEmail  *ratelimit.Limiter
	ResendUser   *ratelimit.Limiter
	LegUser      *ratelimit.Limiter
	Invite       *ratelimit.Limiter // invitations send e-mail
	// Connection searches: per user, and for everyone together under the
	// OJP quota of 50 requests per minute.
	ConnectionsUser *ratelimit.Limiter
	ConnectionsAll  *ratelimit.Limiter
	// Imports sample elevations for every track; Komoot logins are guarded
	// against password guessing through us.
	Import      *ratelimit.Limiter
	KomootLogin *ratelimit.Limiter
	// Comments, reports and photo uploads, per user.
	Comment *ratelimit.Limiter
	Report  *ratelimit.Limiter
	Photo   *ratelimit.Limiter
}

// DefaultLimits are generous for people and tight for scripts.
func DefaultLimits() Limits {
	return Limits{
		LoginIP:         ratelimit.New(6*time.Second, 20), // 10/min sustained
		LoginAccount:    ratelimit.New(30*time.Second, 5), // 2/min per account
		SignupIP:        ratelimit.New(10*time.Minute, 5),
		ForgotIP:        ratelimit.New(10*time.Minute, 5),
		ForgotEmail:     ratelimit.New(20*time.Minute, 3),
		ResendUser:      ratelimit.New(20*time.Minute, 3),
		LegUser:         ratelimit.New(time.Second, 60), // planning bursts, 60/min sustained
		Invite:          ratelimit.New(3*time.Minute, 20),
		ConnectionsUser: ratelimit.New(3*time.Second, 10),
		ConnectionsAll:  ratelimit.New(1500*time.Millisecond, 40), // 40/min
		Import:          ratelimit.New(20*time.Second, 30),
		KomootLogin:     ratelimit.New(2*time.Minute, 5),
		Comment:         ratelimit.New(10*time.Second, 10),
		Report:          ratelimit.New(time.Minute, 10),
		Photo:           ratelimit.New(3*time.Second, 30),
	}
}

// RelaxedLimits are for end-to-end tests, which sign up many accounts from one
// IP. Never use them in production.
func RelaxedLimits() Limits {
	l := DefaultLimits()
	l.SignupIP = ratelimit.New(time.Second, 100)
	return l
}

// Me is the authenticated user's own profile.
type Me struct {
	ID            string    `json:"id" format:"uuid"`
	Email         string    `json:"email" format:"email"`
	EmailVerified bool      `json:"email_verified"`
	Username      string    `json:"username"`
	DisplayName   string    `json:"display_name"`
	Locale        string    `json:"locale"`
	SpeedFactor   float32   `json:"speed_factor" doc:"Personal pace multiplier applied to hiking times"`
	Role          string    `json:"role" enum:"user,moderator,admin"`
	CreatedAt     time.Time `json:"created_at"`
	HasPassword   bool      `json:"has_password" doc:"False for accounts made through a sign-in provider until a password is set"`
	// Notification e-mails.
	NotifyComments bool `json:"notify_comments" doc:"E-mail on comments on my routes and journeys"`
	NotifyFollows  bool `json:"notify_follows" doc:"E-mail when someone follows me"`
}

func toMe(u dbq.User) Me {
	return Me{
		ID:            u.ID.String(),
		Email:         u.Email,
		EmailVerified: u.EmailVerifiedAt != nil,
		Username:      u.Username,
		DisplayName:   u.DisplayName,
		Locale:        u.Locale,
		SpeedFactor:   u.SpeedFactor,
		Role:          u.Role,
		CreatedAt:     u.CreatedAt,

		HasPassword:    u.PasswordHash != nil,
		NotifyComments: u.NotifyComments,
		NotifyFollows:  u.NotifyFollows,
	}
}

type sessionOutput struct {
	SetCookie []http.Cookie `header:"Set-Cookie"`
	Body      struct {
		User Me `json:"user"`
	}
}

type meOutput struct{ Body Me }

type cookieOutput struct {
	SetCookie []http.Cookie `header:"Set-Cookie"`
}

type signupInput struct {
	UserAgent string `header:"User-Agent"`
	Body      struct {
		Email       string `json:"email" format:"email" maxLength:"254"`
		Username    string `json:"username" pattern:"^[a-z0-9_]{3,30}$" doc:"Lowercase letters, digits and underscore"`
		DisplayName string `json:"display_name" minLength:"1" maxLength:"60"`
		Password    string `json:"password" minLength:"10" maxLength:"128"`
		Locale      string `json:"locale,omitempty" enum:"de,en,fr,it" default:"de"`
		Website     string `json:"website,omitempty" doc:"Leave empty (spam trap)"`
	}
}

type loginInput struct {
	UserAgent string `header:"User-Agent"`
	Body      struct {
		Login    string `json:"login" minLength:"3" maxLength:"254" doc:"E-mail address or username"`
		Password string `json:"password" minLength:"1" maxLength:"128"`
	}
}

type tokenInput struct {
	Body struct {
		Token string `json:"token" minLength:"20" maxLength:"100"`
	}
}

type deleteMeInput struct {
	Body struct {
		Password string `json:"password,omitempty" maxLength:"128" doc:"Current password, as confirmation; accounts without one must have logged in within 15 minutes"`
	}
}

type forgotInput struct {
	Body struct {
		Email string `json:"email" format:"email" maxLength:"254"`
	}
}

type resetInput struct {
	Body struct {
		Token    string `json:"token" minLength:"20" maxLength:"100"`
		Password string `json:"password" minLength:"10" maxLength:"128"`
	}
}

var errTooMany = huma.Error429TooManyRequests("too many requests, try again later")

func registerAuth(api huma.API, d Deps) {
	tags := []string{"auth"}
	svc := d.Auth
	lim := d.Limits

	huma.Register(api, huma.Operation{
		OperationID: "signup", Method: http.MethodPost, Path: "/auth/signup",
		Summary: "Create an account and log in", Tags: tags, DefaultStatus: http.StatusCreated,
	}, func(ctx context.Context, in *signupInput) (*sessionOutput, error) {
		if in.Body.Website != "" {
			return nil, huma.Error400BadRequest("invalid request")
		}
		if !lim.SignupIP.Allow(clientIP(ctx)) {
			return nil, errTooMany
		}
		u, sess, err := svc.Signup(ctx, auth.SignupInput{
			Email:       strings.TrimSpace(in.Body.Email),
			Username:    in.Body.Username,
			DisplayName: strings.TrimSpace(in.Body.DisplayName),
			Password:    in.Body.Password,
			Locale:      in.Body.Locale,
		}, in.UserAgent)
		switch {
		case errors.Is(err, auth.ErrEmailTaken):
			return nil, huma.Error409Conflict("email already registered",
				&huma.ErrorDetail{Location: "body.email", Message: "already registered"})
		case errors.Is(err, auth.ErrUsernameTaken):
			return nil, huma.Error409Conflict("username already taken",
				&huma.ErrorDetail{Location: "body.username", Message: "already taken"})
		case err != nil:
			return nil, err
		}
		return d.sessionResponse(u, sess), nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "login", Method: http.MethodPost, Path: "/auth/login",
		Summary: "Log in with e-mail or username", Tags: tags,
	}, func(ctx context.Context, in *loginInput) (*sessionOutput, error) {
		login := strings.ToLower(strings.TrimSpace(in.Body.Login))
		if !lim.LoginIP.Allow(clientIP(ctx)) || !lim.LoginAccount.Allow(login) {
			return nil, errTooMany
		}
		u, sess, err := svc.Login(ctx, login, in.Body.Password, in.UserAgent)
		switch {
		case errors.Is(err, auth.ErrInvalidCredentials):
			return nil, huma.Error401Unauthorized("invalid login or password")
		case errors.Is(err, auth.ErrBanned):
			return nil, huma.Error403Forbidden("account banned")
		case err != nil:
			return nil, err
		}
		return d.sessionResponse(u, sess), nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "logout", Method: http.MethodPost, Path: "/auth/logout",
		Summary: "End the current session", Tags: tags, DefaultStatus: http.StatusNoContent,
	}, func(ctx context.Context, _ *struct{}) (*cookieOutput, error) {
		if t := sessionToken(ctx); t != "" {
			if err := svc.Logout(ctx, t); err != nil {
				return nil, err
			}
		}
		return &cookieOutput{SetCookie: []http.Cookie{clearSessionCookie(d.secureCookies())}}, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "verify-email", Method: http.MethodPost, Path: "/auth/verify-email",
		Summary: "Confirm the e-mail address with the token from the e-mail", Tags: tags,
		DefaultStatus: http.StatusNoContent,
	}, func(ctx context.Context, in *tokenInput) (*struct{}, error) {
		if err := svc.VerifyEmail(ctx, in.Body.Token); errors.Is(err, auth.ErrInvalidToken) {
			return nil, huma.Error400BadRequest("invalid or expired token")
		} else if err != nil {
			return nil, err
		}
		return nil, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "resend-verification", Method: http.MethodPost, Path: "/auth/verify-email/resend",
		Summary: "Send a new verification e-mail", Tags: tags, DefaultStatus: http.StatusNoContent,
	}, func(ctx context.Context, _ *struct{}) (*struct{}, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if u.EmailVerifiedAt != nil {
			return nil, nil
		}
		if !lim.ResendUser.Allow(u.ID.String()) {
			return nil, errTooMany
		}
		return nil, svc.SendVerification(ctx, u)
	})

	huma.Register(api, huma.Operation{
		OperationID: "forgot-password", Method: http.MethodPost, Path: "/auth/password/forgot",
		Summary: "E-mail a password reset link", Description: "Always succeeds so that it does not reveal which addresses have an account.",
		Tags: tags, DefaultStatus: http.StatusNoContent,
	}, func(ctx context.Context, in *forgotInput) (*struct{}, error) {
		email := strings.ToLower(strings.TrimSpace(in.Body.Email))
		if !lim.ForgotIP.Allow(clientIP(ctx)) || !lim.ForgotEmail.Allow(email) {
			return nil, errTooMany
		}
		return nil, svc.ForgotPassword(ctx, email)
	})

	huma.Register(api, huma.Operation{
		OperationID: "reset-password", Method: http.MethodPost, Path: "/auth/password/reset",
		Summary: "Set a new password with a reset token; ends all sessions", Tags: tags,
		DefaultStatus: http.StatusNoContent,
	}, func(ctx context.Context, in *resetInput) (*struct{}, error) {
		if err := svc.ResetPassword(ctx, in.Body.Token, in.Body.Password); errors.Is(err, auth.ErrInvalidToken) {
			return nil, huma.Error400BadRequest("invalid or expired token")
		} else if err != nil {
			return nil, err
		}
		return nil, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-me", Method: http.MethodGet, Path: "/me",
		Summary: "The logged-in user's profile", Tags: []string{"me"},
	}, func(ctx context.Context, _ *struct{}) (*meOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		return &meOutput{Body: toMe(u)}, nil
	})
}

func registerAccount(api huma.API, d Deps) {
	huma.Register(api, huma.Operation{
		OperationID: "delete-me", Method: http.MethodDelete, Path: "/me",
		Summary: "Delete the account and all its routes", Tags: []string{"me"}, DefaultStatus: http.StatusNoContent,
	}, func(ctx context.Context, in *deleteMeInput) (*cookieOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if !d.Limits.LoginAccount.Allow(u.Username) {
			return nil, errTooMany
		}
		if err := d.Auth.DeleteAccount(ctx, u, in.Body.Password, sessionToken(ctx)); err != nil {
			return nil, confirmError(err)
		}
		return &cookieOutput{SetCookie: []http.Cookie{clearSessionCookie(d.secureCookies())}}, nil
	})
}

// confirmError maps a failed auth.Confirm to a response.
func confirmError(err error) error {
	switch {
	case errors.Is(err, auth.ErrInvalidCredentials):
		return huma.Error403Forbidden("wrong password")
	case errors.Is(err, auth.ErrLoginAgain):
		return huma.Error403Forbidden("log in again to confirm")
	}
	return err
}

func (d Deps) sessionResponse(u dbq.User, s auth.Session) *sessionOutput {
	out := &sessionOutput{SetCookie: []http.Cookie{newSessionCookie(s.Token, s.ExpiresAt, d.secureCookies())}}
	out.Body.User = toMe(u)
	return out
}

// secureCookies is false only for plain-HTTP local development.
func (d Deps) secureCookies() bool {
	return !strings.HasPrefix(d.PublicURL, "http://")
}

func requireUser(ctx context.Context) (dbq.User, error) {
	u, ok := auth.UserFrom(ctx)
	if !ok {
		return dbq.User{}, huma.Error401Unauthorized("login required")
	}
	return u, nil
}
