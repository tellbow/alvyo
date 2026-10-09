-- +goose Up
-- Personal access tokens for AI assistants (MCP) and the CLI: they only
-- read. Only the token's SHA-256 is kept; the token is shown once.
CREATE TABLE access_tokens (
    id           uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id      uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    name         text NOT NULL,
    token_hash   bytea NOT NULL UNIQUE,
    created_at   timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz
);
CREATE INDEX access_tokens_user_id_idx ON access_tokens (user_id);

-- +goose Down
DROP TABLE access_tokens;
