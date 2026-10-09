package auth

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/tellbow/alvyo/api/internal/dbq"
)

// AccessTokenPrefix starts every personal access token, so that the
// middleware tells them from session tokens and secret scanners find them.
const AccessTokenPrefix = "alvyo_pat_"

// MaxAccessTokens is how many access tokens one account may have.
const MaxAccessTokens = 20

// accessTokenSeen: last_used_at is written at most this often per token.
const accessTokenSeen = time.Hour

// Access token errors.
var (
	ErrNoAccessToken = errors.New("auth: no such access token")
	ErrTooManyTokens = errors.New("auth: too many access tokens")
)

// AccessToken is a personal access token as its owner sees it, without the
// token itself.
type AccessToken struct {
	ID         uuid.UUID  `json:"id"`
	Name       string     `json:"name"`
	CreatedAt  time.Time  `json:"created_at"`
	LastUsedAt *time.Time `json:"last_used_at,omitempty" doc:"Up to an hour early"`
}

// CreateAccessToken makes a read-only access token for the user and returns it
// with the token, which is not kept and cannot be shown again.
func (s *Service) CreateAccessToken(ctx context.Context, userID uuid.UUID, name string) (AccessToken, string, error) {
	raw, _ := newToken()
	token := AccessTokenPrefix + raw
	t := AccessToken{Name: name}
	err := pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		// The user row is locked so that two requests cannot both pass the count.
		var n int
		if err := tx.QueryRow(ctx, `SELECT (SELECT count(*) FROM access_tokens WHERE user_id = $1)
			FROM users WHERE id = $1 FOR UPDATE`, userID).Scan(&n); err != nil {
			return err
		}
		if n >= MaxAccessTokens {
			return ErrTooManyTokens
		}
		return tx.QueryRow(ctx, `INSERT INTO access_tokens (user_id, name, token_hash) VALUES ($1, $2, $3)
			RETURNING id, created_at`, userID, name, hashToken(token)).Scan(&t.ID, &t.CreatedAt)
	})
	if err != nil {
		return AccessToken{}, "", err
	}
	return t, token, nil
}

// AccessTokens lists the user's access tokens, the newest first.
func (s *Service) AccessTokens(ctx context.Context, userID uuid.UUID) ([]AccessToken, error) {
	rows, err := s.DB.Query(ctx, `SELECT id, name, created_at, last_used_at FROM access_tokens
		WHERE user_id = $1 ORDER BY created_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (AccessToken, error) {
		var t AccessToken
		err := r.Scan(&t.ID, &t.Name, &t.CreatedAt, &t.LastUsedAt)
		return t, err
	})
}

// RevokeAccessToken deletes one of the user's access tokens.
func (s *Service) RevokeAccessToken(ctx context.Context, userID, id uuid.UUID) error {
	tag, err := s.DB.Exec(ctx, `DELETE FROM access_tokens WHERE id = $1 AND user_id = $2`, id, userID)
	if err == nil && tag.RowsAffected() == 0 {
		return ErrNoAccessToken
	}
	return err
}

// AccessTokenUser returns the user of an access token and the token's id;
// ErrNoSession for an unknown or revoked token.
func (s *Service) AccessTokenUser(ctx context.Context, token string) (dbq.User, uuid.UUID, error) {
	var id, userID uuid.UUID
	var lastUsed *time.Time
	err := s.DB.QueryRow(ctx, `SELECT id, user_id, last_used_at FROM access_tokens WHERE token_hash = $1`,
		hashToken(token)).Scan(&id, &userID, &lastUsed)
	if errors.Is(err, pgx.ErrNoRows) {
		return dbq.User{}, uuid.Nil, ErrNoSession
	}
	if err != nil {
		return dbq.User{}, uuid.Nil, err
	}
	u, err := s.q().GetUserByID(ctx, userID)
	if err != nil {
		return dbq.User{}, uuid.Nil, err
	}
	if u.BannedAt != nil {
		return dbq.User{}, uuid.Nil, ErrBanned
	}
	if now := s.now(); lastUsed == nil || now.Sub(*lastUsed) >= accessTokenSeen {
		if _, err := s.DB.Exec(ctx, `UPDATE access_tokens SET last_used_at = $2 WHERE id = $1`, id, now); err != nil {
			return dbq.User{}, uuid.Nil, err
		}
	}
	return u, id, nil
}
