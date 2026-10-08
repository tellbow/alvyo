-- name: CreateUser :one
INSERT INTO users (email, username, display_name, password_hash, locale)
VALUES ($1, $2, $3, $4, $5)
RETURNING *;

-- name: GetUserByID :one
SELECT * FROM users WHERE id = $1;

-- name: GetUserByLogin :one
-- Login accepts either the e-mail address or the username (both citext).
SELECT * FROM users WHERE email = @login OR username = @login;

-- name: GetUserByEmail :one
SELECT * FROM users WHERE email = $1;

-- name: MarkEmailVerified :exec
UPDATE users SET email_verified_at = now() WHERE id = $1 AND email_verified_at IS NULL;

-- name: SetPasswordHash :exec
UPDATE users SET password_hash = $2 WHERE id = $1;

-- name: CreateSession :exec
INSERT INTO sessions (token_hash, user_id, expires_at, user_agent)
VALUES ($1, $2, $3, $4);

-- name: GetSessionUser :one
SELECT sqlc.embed(users), sessions.expires_at AS session_expires_at
FROM sessions JOIN users ON users.id = sessions.user_id
WHERE sessions.token_hash = $1 AND sessions.expires_at > now();

-- name: ExtendSession :exec
-- Never past SessionMaxAge (180 days) after the login.
UPDATE sessions SET expires_at = least($2, created_at + interval '180 days'), last_seen_at = now() WHERE token_hash = $1;

-- name: DeleteSession :exec
DELETE FROM sessions WHERE token_hash = $1;

-- name: DeleteUserSessions :exec
DELETE FROM sessions WHERE user_id = $1;

-- name: CreateEmailToken :exec
INSERT INTO email_tokens (token_hash, purpose, user_id, expires_at)
VALUES ($1, $2, $3, $4);

-- name: UseEmailToken :one
-- Marks a valid, unused token as used and returns its user; no row if invalid.
UPDATE email_tokens SET used_at = now()
WHERE token_hash = $1 AND purpose = $2 AND used_at IS NULL AND expires_at > now()
RETURNING user_id;

-- name: DeleteUser :exec
-- Cascades to sessions, e-mail tokens and routes.
DELETE FROM users WHERE id = $1;
