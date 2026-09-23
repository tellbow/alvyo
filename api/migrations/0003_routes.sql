-- +goose Up
CREATE TYPE visibility AS ENUM ('private', 'unlisted', 'public');

CREATE TABLE routes (
    id                 uuid PRIMARY KEY DEFAULT uuidv7(),
    owner_id           uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    title              text NOT NULL CHECK (length(title) BETWEEN 1 AND 120),
    description        text NOT NULL DEFAULT '',
    visibility         visibility NOT NULL DEFAULT 'private',
    share_token        text UNIQUE,
    profile            text NOT NULL DEFAULT 'hike' CHECK (profile IN ('hike', 'alpine')),
    -- Planner state: anchors and the computed legs (geometry, details, stats),
    -- so editing resumes without routing again.
    anchors            jsonb NOT NULL,
    legs               jsonb NOT NULL,
    -- The whole line (legs joined) for spatial queries and GPX.
    geom               geometry(LineStringZ, 4326) NOT NULL,
    start_point        geometry(Point, 4326) GENERATED ALWAYS AS (ST_Force2D(ST_StartPoint(geom))) STORED,
    distance_m         integer NOT NULL,
    ascent_m           integer NOT NULL,
    descent_m          integer NOT NULL,
    duration_s         integer NOT NULL,
    duration_reverse_s integer NOT NULL,
    ele_min_m          integer NOT NULL,
    ele_max_m          integer NOT NULL,
    sac_grade          smallint NOT NULL,
    sac_max            smallint NOT NULL,
    version            integer NOT NULL DEFAULT 1,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX routes_geom_idx ON routes USING gist (geom);
CREATE INDEX routes_start_idx ON routes USING gist (start_point);
CREATE INDEX routes_owner_idx ON routes (owner_id, updated_at DESC);
CREATE INDEX routes_public_idx ON routes (updated_at DESC) WHERE visibility = 'public';

-- +goose Down
DROP TABLE routes;
DROP TYPE visibility;
