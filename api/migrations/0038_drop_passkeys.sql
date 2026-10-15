-- +goose Up
-- Passkeys are gone; accounts that had only a passkey set a password with
-- «Passwort vergessen?».
DROP TABLE passkeys;

-- +goose Down
CREATE TABLE passkeys (
    id           bytea PRIMARY KEY,
    user_id      uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    name         text NOT NULL CHECK (length(name) BETWEEN 1 AND 60),
    credential   jsonb NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz
);
CREATE INDEX passkeys_user_idx ON passkeys (user_id);
