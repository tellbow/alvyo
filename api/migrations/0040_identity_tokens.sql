-- +goose Up
-- Apple's refresh token, to revoke the sign-in when the identity goes (App
-- Store guideline 5.1.1(v)), and the client id it was issued to: the
-- website's Services ID or the app's bundle id.
ALTER TABLE identities ADD COLUMN refresh_token text, ADD COLUMN token_client text;

-- +goose Down
ALTER TABLE identities DROP COLUMN refresh_token, DROP COLUMN token_client;
