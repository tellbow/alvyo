// Package auth handles accounts, sessions and e-mail tokens.
package auth

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/url"
	"time"

	"github.com/go-webauthn/webauthn/webauthn"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tellbow/alvyo/api/internal/dbq"
	"github.com/tellbow/alvyo/api/internal/mailer"
)

const (
	// SessionTTL is how long a session lasts without activity.
	SessionTTL = 30 * 24 * time.Hour
	// Sessions are extended at most once a day to save writes.
	sessionRefreshAfter = 24 * time.Hour

	verifyTokenTTL = 48 * time.Hour
	resetTokenTTL  = time.Hour
)

// Errors returned to API handlers.
var (
	ErrEmailTaken         = errors.New("email already registered")
	ErrUsernameTaken      = errors.New("username already taken")
	ErrInvalidCredentials = errors.New("invalid login or password")
	ErrInvalidToken       = errors.New("invalid or expired token")
	ErrBanned             = errors.New("account banned")
	ErrNoSession          = errors.New("no valid session")
)

// Service implements account and session logic.
type Service struct {
	DB        *pgxpool.Pool
	Mail      mailer.Sender
	PublicURL string // base URL of the web app for links in e-mails
	Now       func() time.Time
	// WebAuthn enables passkeys (NewWebAuthn); nil turns them off.
	WebAuthn *webauthn.WebAuthn

	passkeyCeremonies ceremonies
}

func (s *Service) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

func (s *Service) q() *dbq.Queries { return dbq.New(s.DB) }

// SignupInput holds the fields of a new account.
type SignupInput struct {
	Email       string
	Username    string
	DisplayName string
	Password    string
	Locale      string
}

// Session is a newly created login session.
type Session struct {
	Token     string
	ExpiresAt time.Time
}

// Signup creates an account, logs it in and sends the verification e-mail.
func (s *Service) Signup(ctx context.Context, in SignupInput, userAgent string) (dbq.User, Session, error) {
	hash, err := HashPassword(in.Password)
	if err != nil {
		return dbq.User{}, Session{}, err
	}
	u, err := s.q().CreateUser(ctx, dbq.CreateUserParams{
		Email:        in.Email,
		Username:     in.Username,
		DisplayName:  in.DisplayName,
		PasswordHash: &hash,
		Locale:       in.Locale,
	})
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			switch pgErr.ConstraintName {
			case "users_email_key":
				return dbq.User{}, Session{}, ErrEmailTaken
			case "users_username_key":
				return dbq.User{}, Session{}, ErrUsernameTaken
			}
		}
		return dbq.User{}, Session{}, fmt.Errorf("auth: create user: %w", err)
	}

	// A failed e-mail must not fail the signup; the user can request a new one.
	if err := s.SendVerification(ctx, u); err != nil {
		slog.ErrorContext(ctx, "sending verification e-mail", "user", u.ID, "err", err)
	}
	sess, err := s.createSession(ctx, u, userAgent)
	return u, sess, err
}

// SendVerification e-mails a new verification link to the user.
func (s *Service) SendVerification(ctx context.Context, u dbq.User) error {
	token, hash := newToken()
	if err := s.q().CreateEmailToken(ctx, dbq.CreateEmailTokenParams{
		TokenHash: hash, Purpose: "verify", UserID: u.ID, ExpiresAt: s.now().Add(verifyTokenTTL),
	}); err != nil {
		return err
	}
	return s.Mail.Send(ctx, verificationMail(u, s.link("/verify-email", token)))
}

// VerifyEmail consumes a verification token and marks the address verified.
func (s *Service) VerifyEmail(ctx context.Context, token string) error {
	userID, err := s.q().UseEmailToken(ctx, dbq.UseEmailTokenParams{TokenHash: hashToken(token), Purpose: "verify"})
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrInvalidToken
	}
	if err != nil {
		return err
	}
	return s.q().MarkEmailVerified(ctx, userID)
}

// dummyHash is verified when the login is unknown so that response times do
// not reveal which accounts exist.
var dummyHash, _ = HashPassword("alvyo-timing-equaliser")

// Login checks the credentials (e-mail or username) and starts a session.
func (s *Service) Login(ctx context.Context, login, password, userAgent string) (dbq.User, Session, error) {
	u, err := s.q().GetUserByLogin(ctx, login)
	if errors.Is(err, pgx.ErrNoRows) || (err == nil && u.PasswordHash == nil) {
		_, _ = VerifyPassword(password, dummyHash)
		return dbq.User{}, Session{}, ErrInvalidCredentials
	}
	if err != nil {
		return dbq.User{}, Session{}, err
	}
	ok, err := VerifyPassword(password, *u.PasswordHash)
	if err != nil {
		return dbq.User{}, Session{}, err
	}
	if !ok {
		return dbq.User{}, Session{}, ErrInvalidCredentials
	}
	if u.BannedAt != nil {
		return dbq.User{}, Session{}, ErrBanned
	}
	sess, err := s.createSession(ctx, u, userAgent)
	return u, sess, err
}

func (s *Service) createSession(ctx context.Context, u dbq.User, userAgent string) (Session, error) {
	token, hash := newToken()
	expires := s.now().Add(SessionTTL)
	var ua *string
	if userAgent != "" {
		ua = &userAgent
	}
	if err := s.q().CreateSession(ctx, dbq.CreateSessionParams{
		TokenHash: hash, UserID: u.ID, ExpiresAt: expires, UserAgent: ua,
	}); err != nil {
		return Session{}, fmt.Errorf("auth: create session: %w", err)
	}
	return Session{Token: token, ExpiresAt: expires}, nil
}

// SessionUser returns the user of a valid session. If the session was
// extended, extended holds the new expiry so the cookie can be renewed.
func (s *Service) SessionUser(ctx context.Context, token string) (u dbq.User, extended *time.Time, err error) {
	row, err := s.q().GetSessionUser(ctx, hashToken(token))
	if errors.Is(err, pgx.ErrNoRows) {
		return dbq.User{}, nil, ErrNoSession
	}
	if err != nil {
		return dbq.User{}, nil, err
	}
	if row.User.BannedAt != nil {
		return dbq.User{}, nil, ErrBanned
	}
	now := s.now()
	if row.SessionExpiresAt.Sub(now) < SessionTTL-sessionRefreshAfter {
		expires := now.Add(SessionTTL)
		if err := s.q().ExtendSession(ctx, dbq.ExtendSessionParams{TokenHash: hashToken(token), ExpiresAt: expires}); err != nil {
			return dbq.User{}, nil, err
		}
		extended = &expires
	}
	return row.User, extended, nil
}

// recentLogin is how fresh a session must be to stand in for the password
// of an account without one.
const recentLogin = 15 * time.Minute

// Confirm checks that the person at the keyboard owns the account before a
// sensitive change: by the password, or for accounts without one (provider
// logins) by a login in the last 15 minutes on the session token.
func (s *Service) Confirm(ctx context.Context, u dbq.User, password, sessionToken string) error {
	if u.PasswordHash != nil {
		ok, err := VerifyPassword(password, *u.PasswordHash)
		if err != nil {
			return err
		}
		if !ok {
			return ErrInvalidCredentials
		}
		return nil
	}
	return s.RecentLogin(ctx, u, sessionToken)
}

// RecentLogin checks that the session was logged in within the last 15
// minutes (ErrLoginAgain otherwise).
func (s *Service) RecentLogin(ctx context.Context, u dbq.User, sessionToken string) error {
	var fresh bool
	err := s.DB.QueryRow(ctx, `SELECT created_at > $2 FROM sessions WHERE token_hash = $1 AND user_id = $3`,
		hashToken(sessionToken), s.now().Add(-recentLogin), u.ID).Scan(&fresh)
	if err != nil || !fresh {
		return ErrLoginAgain
	}
	return nil
}

// ErrLoginAgain asks an account without password to log in again first.
var ErrLoginAgain = errors.New("auth: log in again to confirm")

// DeleteAccount removes a user and everything they own after Confirm.
func (s *Service) DeleteAccount(ctx context.Context, u dbq.User, password, sessionToken string) error {
	if err := s.Confirm(ctx, u, password, sessionToken); err != nil {
		return err
	}
	return s.q().DeleteUser(ctx, u.ID)
}

// Logout ends a session.
func (s *Service) Logout(ctx context.Context, token string) error {
	return s.q().DeleteSession(ctx, hashToken(token))
}

// ForgotPassword e-mails a reset link if the address belongs to an account.
// It never reports whether the account exists.
func (s *Service) ForgotPassword(ctx context.Context, email string) error {
	u, err := s.q().GetUserByEmail(ctx, email)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	token, hash := newToken()
	if err := s.q().CreateEmailToken(ctx, dbq.CreateEmailTokenParams{
		TokenHash: hash, Purpose: "reset", UserID: u.ID, ExpiresAt: s.now().Add(resetTokenTTL),
	}); err != nil {
		return err
	}
	return s.Mail.Send(ctx, resetMail(u, s.link("/reset-password", token)))
}

// ResetPassword sets a new password with a reset token and ends all sessions.
// Receiving the e-mail also proves the address, so it counts as verified.
func (s *Service) ResetPassword(ctx context.Context, token, password string) error {
	return pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		q := dbq.New(tx)
		userID, err := q.UseEmailToken(ctx, dbq.UseEmailTokenParams{TokenHash: hashToken(token), Purpose: "reset"})
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrInvalidToken
		}
		if err != nil {
			return err
		}
		// Provider accounts connected before the address was proven may be
		// a stranger's who signed up with it; its owner takes over alone.
		// (Passkeys need a verified address.)
		if _, err := tx.Exec(ctx, `DELETE FROM identities WHERE user_id = $1
			AND (SELECT email_verified_at IS NULL FROM users WHERE id = $1)`, userID); err != nil {
			return err
		}
		// Hashed only for a valid token: hashing is costly by design.
		hash, err := HashPassword(password)
		if err != nil {
			return err
		}
		if err := q.SetPasswordHash(ctx, dbq.SetPasswordHashParams{ID: userID, PasswordHash: &hash}); err != nil {
			return err
		}
		if err := q.MarkEmailVerified(ctx, userID); err != nil {
			return err
		}
		return q.DeleteUserSessions(ctx, userID)
	})
}

func (s *Service) link(path, token string) string {
	return s.PublicURL + path + "?token=" + url.QueryEscape(token)
}
