-- +goose Up
-- People a hiker shares their live position with.
CREATE TABLE contacts (
    id         uuid PRIMARY KEY DEFAULT uuidv7(),
    owner_id   uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    name       text NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
    email      citext NOT NULL CHECK (length(email) <= 254),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (owner_id, email)
);

-- A hike shared live: the link's token, when it should end, the last
-- position; deleted 7 days after the end.
CREATE TABLE live_shares (
    id           uuid PRIMARY KEY DEFAULT uuidv7(),
    owner_id     uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    route_id     uuid REFERENCES routes ON DELETE SET NULL,
    title        text NOT NULL CHECK (length(title) BETWEEN 1 AND 120),
    token        text NOT NULL UNIQUE,
    started_at   timestamptz NOT NULL DEFAULT now(),
    expected_end timestamptz NOT NULL,
    ended_at     timestamptz,
    alerted_at   timestamptz, -- the overdue e-mail went out
    last_lon     double precision,
    last_lat     double precision,
    last_at      timestamptz
);
CREATE INDEX live_shares_open_idx ON live_shares (expected_end) WHERE ended_at IS NULL;
CREATE INDEX live_shares_owner_idx ON live_shares (owner_id);

-- Who gets the link and the alerts, as the contacts were at the start.
CREATE TABLE live_recipients (
    share_id uuid NOT NULL REFERENCES live_shares ON DELETE CASCADE,
    name     text NOT NULL,
    email    citext NOT NULL,
    PRIMARY KEY (share_id, email)
);

-- The way so far, one position per 5 minutes.
CREATE TABLE live_positions (
    share_id uuid NOT NULL REFERENCES live_shares ON DELETE CASCADE,
    at       timestamptz NOT NULL,
    lon      double precision NOT NULL,
    lat      double precision NOT NULL,
    PRIMARY KEY (share_id, at)
);

-- +goose Down
DROP TABLE live_positions;
DROP TABLE live_recipients;
DROP TABLE live_shares;
DROP TABLE contacts;
