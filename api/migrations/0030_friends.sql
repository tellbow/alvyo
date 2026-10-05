-- +goose Up
-- Friends, both ways: one asks, the other accepts, or at once through the
-- invite link someone sent (friend_token). A public profile is found by
-- the user search; a private one is seen by friends only.
ALTER TABLE users
    ADD COLUMN profile_public boolean NOT NULL DEFAULT true,
    ADD COLUMN friend_token   text UNIQUE;

CREATE TABLE friendships (
    requester_id uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    addressee_id uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    created_at   timestamptz NOT NULL DEFAULT now(),
    accepted_at  timestamptz, -- null while asked
    PRIMARY KEY (requester_id, addressee_id),
    CHECK (requester_id <> addressee_id)
);
-- One per pair, whoever asked.
CREATE UNIQUE INDEX friendships_pair_idx ON friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
CREATE INDEX friendships_addressee_idx ON friendships (addressee_id);

-- +goose Down
DROP TABLE friendships;
ALTER TABLE users DROP COLUMN profile_public, DROP COLUMN friend_token;
