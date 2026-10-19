package auth

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/tellbow/alvyo/api/internal/dbq"
)

// Identity errors.
var (
	// ErrIdentityTaken: the provider account belongs to another Alvyo account.
	ErrIdentityTaken = errors.New("auth: this provider account is connected to another account")
	// ErrProviderLinked: the account already has an identity at this provider.
	ErrProviderLinked = errors.New("auth: already connected to this provider")
	// ErrNoEmail: the provider gave no e-mail address for a new account.
	ErrNoEmail = errors.New("auth: the provider gave no e-mail address")
	// ErrSignupLimit: too many new accounts from here for now.
	ErrSignupLimit = errors.New("auth: too many sign-ups")
)

// IdentityLogin logs in the account connected to id, or creates one when
// no account uses the e-mail address and allowNew agrees (the sign-up rate
// limit). An existing account with the address is not logged in
// (ErrEmailTaken): its owner connects the provider from the account page
// first.
func (s *Service) IdentityLogin(ctx context.Context, id Identity, locale, userAgent string, allowNew func() bool) (dbq.User, Session, error) {
	var userID uuid.UUID
	err := s.DB.QueryRow(ctx, `UPDATE identities SET last_used_at = now(),
			refresh_token = coalesce(nullif($3, ''), refresh_token), token_client = coalesce(nullif($4, ''), token_client)
		WHERE provider = $1 AND subject = $2
		RETURNING user_id`, id.Provider, id.Subject, id.RefreshToken, id.TokenClient).Scan(&userID)
	switch {
	case err == nil:
		u, err := s.q().GetUserByID(ctx, userID)
		if err != nil {
			return dbq.User{}, Session{}, err
		}
		if u.BannedAt != nil {
			return dbq.User{}, Session{}, ErrBanned
		}
		sess, err := s.createSession(ctx, u, userAgent)
		return u, sess, err
	case !errors.Is(err, pgx.ErrNoRows):
		return dbq.User{}, Session{}, err
	}

	if id.Email == "" {
		return dbq.User{}, Session{}, ErrNoEmail
	}
	if _, err := s.q().GetUserByEmail(ctx, id.Email); err == nil {
		return dbq.User{}, Session{}, ErrEmailTaken
	} else if !errors.Is(err, pgx.ErrNoRows) {
		return dbq.User{}, Session{}, err
	}
	if !allowNew() {
		return dbq.User{}, Session{}, ErrSignupLimit
	}
	u, err := s.createProviderUser(ctx, id, locale)
	if err != nil {
		return dbq.User{}, Session{}, err
	}
	if u.EmailVerifiedAt == nil {
		if err := s.SendVerification(ctx, u); err != nil {
			slog.ErrorContext(ctx, "sending verification e-mail", "user", u.ID, "err", err)
		}
	}
	sess, err := s.createSession(ctx, u, userAgent)
	return u, sess, err
}

var notUsername = regexp.MustCompile(`[^a-z0-9_]+`)

// usernameFrom makes a valid username (3–30 of a-z, 0-9, _) from a hint.
func usernameFrom(hint string) string {
	name := strings.Trim(notUsername.ReplaceAllString(strings.ToLower(hint), "_"), "_")
	if len(name) > 26 {
		name = name[:26]
	}
	for len(name) < 3 {
		name += "_"
	}
	return name
}

// createProviderUser creates an account without password for a new
// identity, with a free username derived from the provider's data.
func (s *Service) createProviderUser(ctx context.Context, id Identity, locale string) (dbq.User, error) {
	hint := id.Username
	if hint == "" {
		hint, _, _ = strings.Cut(id.Email, "@")
	}
	base := usernameFrom(hint)
	display := id.Name
	if display == "" {
		display = base
	}
	if r := []rune(display); len(r) > 60 {
		display = string(r[:60])
	}
	for i := 1; i <= 20; i++ {
		username := base
		if i > 1 {
			username = base + strconv.Itoa(i)
		}
		var u dbq.User
		err := pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
			q := dbq.New(tx)
			var err error
			u, err = q.CreateUser(ctx, dbq.CreateUserParams{
				Email: id.Email, Username: username, DisplayName: display, Locale: locale,
			})
			if err != nil {
				return err
			}
			if id.EmailVerified {
				if err := q.MarkEmailVerified(ctx, u.ID); err != nil {
					return err
				}
				now := s.now()
				u.EmailVerifiedAt = &now
			}
			return insertIdentity(ctx, tx, u.ID, id)
		})
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			switch pgErr.ConstraintName {
			case "users_username_key":
				continue // try the next number
			case "users_email_key":
				return dbq.User{}, ErrEmailTaken
			case "identities_pkey":
				return dbq.User{}, ErrIdentityTaken
			}
		}
		if err != nil {
			return dbq.User{}, fmt.Errorf("auth: create provider user: %w", err)
		}
		return u, nil
	}
	return dbq.User{}, fmt.Errorf("auth: no free username for %q", base)
}

// LinkIdentity connects a provider account to the logged-in user.
func (s *Service) LinkIdentity(ctx context.Context, user uuid.UUID, id Identity) error {
	err := insertIdentity(ctx, s.DB, user, id)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		if pgErr.ConstraintName == "identities_pkey" {
			var owner uuid.UUID
			if s.DB.QueryRow(ctx, `SELECT user_id FROM identities WHERE provider = $1 AND subject = $2`,
				id.Provider, id.Subject).Scan(&owner) == nil && owner == user {
				return nil // connected before
			}
			return ErrIdentityTaken
		}
		return ErrProviderLinked
	}
	return err
}

func insertIdentity(ctx context.Context, db interface {
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
}, user uuid.UUID, id Identity) error {
	_, err := db.Exec(ctx, `INSERT INTO identities (provider, subject, user_id, email, last_used_at, refresh_token, token_client)
		VALUES ($1, $2, $3, nullif($4, ''), now(), nullif($5, ''), nullif($6, ''))`,
		id.Provider, id.Subject, user, id.Email, id.RefreshToken, id.TokenClient)
	return err
}

// IdentityInfo is a connected provider account.
type IdentityInfo struct {
	Provider string     `json:"provider"`
	Email    string     `json:"email,omitempty"`
	Created  time.Time  `json:"created_at"`
	LastUsed *time.Time `json:"last_used_at,omitempty"`
}

// Identities lists the provider accounts connected to a user.
func (s *Service) Identities(ctx context.Context, user uuid.UUID) ([]IdentityInfo, error) {
	rows, err := s.DB.Query(ctx, `SELECT provider, coalesce(email, ''), created_at, last_used_at
		FROM identities WHERE user_id = $1 ORDER BY provider`, user)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (IdentityInfo, error) {
		var i IdentityInfo
		err := r.Scan(&i.Provider, &i.Email, &i.Created, &i.LastUsed)
		return i, err
	})
}

// UnlinkIdentity disconnects a provider (not the last way to log in).
func (s *Service) UnlinkIdentity(ctx context.Context, u dbq.User, provider string) error {
	var gone []revocable
	err := pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		var err error
		gone, err = deleteIdentities(ctx, tx, `user_id = $1 AND provider = $2`, u.ID, provider)
		if err != nil {
			return err
		}
		if len(gone) == 0 {
			return ErrUnknownProvider
		}
		return lastLogin(ctx, tx, u)
	})
	if err == nil {
		s.revoke(ctx, gone)
	}
	return err
}

// DropIdentity removes an identity the provider says is gone (the person
// stopped using it with Alvyo, or deleted their account there). Its tokens
// are revoked already. The account stays: a password reset by e-mail
// still opens it.
func (s *Service) DropIdentity(ctx context.Context, provider, subject string) error {
	_, err := s.DB.Exec(ctx, `DELETE FROM identities WHERE provider = $1 AND subject = $2`, provider, subject)
	return err
}

// revocable is a provider's refresh token, to revoke once its identity is
// gone.
type revocable struct{ provider, client, token string }

// deleteIdentities deletes the identities matching where and returns them.
func deleteIdentities(ctx context.Context, tx pgx.Tx, where string, args ...any) ([]revocable, error) {
	rows, err := tx.Query(ctx, `DELETE FROM identities WHERE `+where+`
		RETURNING provider, coalesce(token_client, ''), coalesce(refresh_token, '')`, args...)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (revocable, error) {
		var v revocable
		err := r.Scan(&v.provider, &v.client, &v.token)
		return v, err
	})
}

// revoke ends the sign-ins at the providers that gave tokens, after the
// identities are gone; a failure is logged, not shown.
func (s *Service) revoke(ctx context.Context, gone []revocable) {
	if s.Revoke == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 10*time.Second)
	defer cancel()
	for _, g := range gone {
		if g.token == "" {
			continue
		}
		if err := s.Revoke(ctx, g.provider, g.client, g.token); err != nil {
			slog.ErrorContext(ctx, "revoking a sign-in", "provider", g.provider, "err", err)
		}
	}
}

// lastLogin fails with ErrLastLogin (rolling back tx) if u has no way left
// to log in: no password or provider account.
func lastLogin(ctx context.Context, tx pgx.Tx, u dbq.User) error {
	var ok bool
	if err := tx.QueryRow(ctx, `SELECT password_hash IS NOT NULL
		OR EXISTS (SELECT 1 FROM identities WHERE user_id = $1)
		FROM users WHERE id = $1`, u.ID).Scan(&ok); err != nil {
		return err
	}
	if !ok {
		return ErrLastLogin
	}
	return nil
}

// ErrLastLogin means a change would leave the account without a way to log
// in.
var ErrLastLogin = errors.New("auth: this is the last way to log in")
