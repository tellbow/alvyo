-- +goose Up
-- Passkeys (WebAuthn credentials) and accounts at outside OpenID Connect
-- providers, as further ways to log in.
CREATE TABLE passkeys (
    id           bytea PRIMARY KEY, -- credential id
    user_id      uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    name         text NOT NULL CHECK (length(name) BETWEEN 1 AND 60),
    credential   jsonb NOT NULL,    -- webauthn.Credential: public key, sign count, flags
    created_at   timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz
);
CREATE INDEX passkeys_user_idx ON passkeys (user_id);

CREATE TABLE identities (
    provider     text NOT NULL, -- id from the configuration, e.g. "google"
    subject      text NOT NULL, -- the provider's stable user id (sub)
    user_id      uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    email        citext,        -- as the provider reported it, for display
    created_at   timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz,
    PRIMARY KEY (provider, subject),
    UNIQUE (user_id, provider)
);

-- +goose Down
DROP TABLE identities;
DROP TABLE passkeys;
