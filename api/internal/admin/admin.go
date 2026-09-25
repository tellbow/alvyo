// Package admin implements the moderation commands of the alvyo CLI.
package admin

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotFound means the user or route does not exist.
var ErrNotFound = errors.New("not found")

// Ban blocks a user from logging in and ends all their sessions. Their
// routes, journeys and collections become private.
func Ban(ctx context.Context, db *pgxpool.Pool, username string) error {
	tx, err := db.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	var id uuid.UUID
	if err := tx.QueryRow(ctx, `SELECT id FROM users WHERE username = $1`, username).Scan(&id); err != nil {
		return notFound(err)
	}
	if err := BanUser(ctx, tx, id); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// BanUser bans the user with the given id inside tx (see Ban).
func BanUser(ctx context.Context, tx pgx.Tx, id uuid.UUID) error {
	if _, err := tx.Exec(ctx, `UPDATE users SET banned_at = now() WHERE id = $1`, id); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `DELETE FROM sessions WHERE user_id = $1`, id); err != nil {
		return err
	}
	for _, table := range []string{"routes", "journeys", "collections"} {
		if _, err := tx.Exec(ctx, `UPDATE `+table+` SET visibility = 'private', version = version + 1, updated_at = now()
			WHERE owner_id = $1 AND visibility <> 'private'`, id); err != nil {
			return err
		}
	}
	return nil
}

// Unban lets a user log in again. Their content stays private until they
// share it again.
func Unban(ctx context.Context, db *pgxpool.Pool, username string) error {
	res, err := db.Exec(ctx, `UPDATE users SET banned_at = NULL WHERE username = $1`, username)
	if err == nil && res.RowsAffected() == 0 {
		return ErrNotFound
	}
	return err
}

// SetRole changes a user's role (user, moderator, admin).
func SetRole(ctx context.Context, db *pgxpool.Pool, username, role string) error {
	res, err := db.Exec(ctx, `UPDATE users SET role = $2 WHERE username = $1`, username, role)
	if err == nil && res.RowsAffected() == 0 {
		return ErrNotFound
	}
	return err
}

// Unpublish makes a route private (e.g. after a report).
func Unpublish(ctx context.Context, db *pgxpool.Pool, routeID string) error {
	res, err := db.Exec(ctx, `UPDATE routes SET visibility = 'private', version = version + 1, updated_at = now() WHERE id = $1`, routeID)
	if err == nil && res.RowsAffected() == 0 {
		return ErrNotFound
	}
	return err
}

func notFound(err error) error {
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	return fmt.Errorf("admin: %w", err)
}
