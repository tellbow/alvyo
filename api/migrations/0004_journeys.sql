-- +goose Up
-- A journey is a multi-day or multi-week hike made of ordered stages, each
-- with its own route. Stage routes belong to the journey (routes.journey_id):
-- their visibility and share link are the journey's.
CREATE TABLE journeys (
    id          uuid PRIMARY KEY DEFAULT uuidv7(),
    owner_id    uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    title       text NOT NULL CHECK (length(title) BETWEEN 1 AND 120),
    description text NOT NULL DEFAULT '',
    visibility  visibility NOT NULL DEFAULT 'private',
    share_token text UNIQUE,
    version     integer NOT NULL DEFAULT 1,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX journeys_owner_idx ON journeys (owner_id, updated_at DESC);

ALTER TABLE routes ADD COLUMN journey_id uuid REFERENCES journeys ON DELETE CASCADE;
CREATE INDEX routes_journey_idx ON routes (journey_id);

CREATE TYPE stage_status AS ENUM ('planned', 'done', 'skipped');

CREATE TABLE stages (
    id              uuid PRIMARY KEY DEFAULT uuidv7(),
    journey_id      uuid NOT NULL REFERENCES journeys ON DELETE CASCADE,
    position        integer NOT NULL,
    title           text NOT NULL DEFAULT '' CHECK (length(title) <= 120),
    route_id        uuid UNIQUE REFERENCES routes ON DELETE SET NULL,
    planned_date    date,
    status          stage_status NOT NULL DEFAULT 'planned',
    done_on         date,
    -- How the hiker gets from the previous stage's end to this start when they
    -- are apart (train, cable car …); acknowledges the gap.
    transfer_before text CHECK (transfer_before IN ('pt', 'cablecar', 'other')),
    notes           text NOT NULL DEFAULT '' CHECK (length(notes) <= 5000),
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT stages_position_key UNIQUE (journey_id, position) DEFERRABLE INITIALLY DEFERRED
);

-- +goose Down
DROP TABLE stages;
DROP TYPE stage_status;
ALTER TABLE routes DROP COLUMN journey_id;
DROP TABLE journeys;
