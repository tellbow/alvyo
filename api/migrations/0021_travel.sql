-- +goose Up
-- Where a user sets off from and returns to by public transport.
CREATE TABLE homes (
    id         uuid PRIMARY KEY DEFAULT uuidv7(),
    owner_id   uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    name       text NOT NULL CHECK (length(name) BETWEEN 1 AND 60),
    address    text NOT NULL CHECK (length(address) <= 200),
    lon        double precision NOT NULL CHECK (lon BETWEEN -180 AND 180),
    lat        double precision NOT NULL CHECK (lat BETWEEN -90 AND 90),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX homes_owner_idx ON homes (owner_id);

-- A user's way to a journey's first stage (to) and home from its last
-- (back): from or to which home, leaving after or arriving before a time on
-- the stage's day. Each person's own; no one else sees it.
CREATE TABLE journey_travel (
    user_id    uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    journey_id uuid NOT NULL REFERENCES journeys ON DELETE CASCADE,
    direction  text NOT NULL CHECK (direction IN ('to', 'back')),
    home_id    uuid NOT NULL REFERENCES homes ON DELETE CASCADE,
    at_time    text NOT NULL CHECK (at_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
    arrive     boolean NOT NULL DEFAULT false,
    PRIMARY KEY (user_id, journey_id, direction)
);

-- +goose Down
DROP TABLE journey_travel;
DROP TABLE homes;
