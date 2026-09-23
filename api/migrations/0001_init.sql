-- +goose Up
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE users (
    id                uuid PRIMARY KEY DEFAULT uuidv7(),
    email             citext NOT NULL UNIQUE,
    email_verified_at timestamptz,
    password_hash     text,          -- argon2id PHC string; NULL for passwordless accounts
    username          citext NOT NULL UNIQUE CHECK (username ~ '^[a-z0-9_]{3,30}$'),
    display_name      text NOT NULL,
    locale            text NOT NULL DEFAULT 'de',
    speed_factor      real NOT NULL DEFAULT 1.0 CHECK (speed_factor BETWEEN 0.3 AND 3.0),
    role              text NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'moderator', 'admin')),
    banned_at         timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now()
);

-- Only the SHA-256 of the opaque session token is stored.
CREATE TABLE sessions (
    token_hash   bytea PRIMARY KEY,
    user_id      uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    created_at   timestamptz NOT NULL DEFAULT now(),
    expires_at   timestamptz NOT NULL,
    last_seen_at timestamptz,
    user_agent   text
);
CREATE INDEX sessions_user_id_idx ON sessions (user_id);

CREATE TABLE email_tokens (
    token_hash bytea PRIMARY KEY,
    purpose    text NOT NULL CHECK (purpose IN ('verify', 'reset')),
    user_id    uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    expires_at timestamptz NOT NULL,
    used_at    timestamptz
);
CREATE INDEX email_tokens_user_id_idx ON email_tokens (user_id);

-- +goose Down
DROP TABLE email_tokens;
DROP TABLE sessions;
DROP TABLE users;
