-- +goose Up
-- When and by whom a route's line was saved (title and visibility changes
-- aside); NULL: its owner.
ALTER TABLE routes ADD COLUMN content_at timestamptz, ADD COLUMN content_by uuid REFERENCES users ON DELETE SET NULL;
UPDATE routes SET content_at = updated_at;
ALTER TABLE routes ALTER COLUMN content_at SET NOT NULL, ALTER COLUMN content_at SET DEFAULT now();

-- The earlier versions of a route's line, the last 20 (routes.MaxRevisions).
CREATE TABLE route_revisions (
    route_id   uuid NOT NULL REFERENCES routes ON DELETE CASCADE,
    version    integer NOT NULL,
    profile    text NOT NULL,
    anchors    jsonb NOT NULL,
    legs       jsonb NOT NULL,
    distance_m integer NOT NULL,
    ascent_m   integer NOT NULL,
    duration_s integer NOT NULL,
    saved_at   timestamptz NOT NULL,
    saved_by   uuid REFERENCES users ON DELETE SET NULL,
    PRIMARY KEY (route_id, version)
);

-- +goose Down
DROP TABLE route_revisions;
ALTER TABLE routes DROP COLUMN content_at, DROP COLUMN content_by;
