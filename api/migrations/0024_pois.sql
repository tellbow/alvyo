-- +goose Up
-- Points of interest along routes, from OpenStreetMap (import-places.sh):
-- apart from places, which are stage starts and ends.
CREATE TABLE pois (
    id        uuid PRIMARY KEY DEFAULT uuidv7(),
    kind      text NOT NULL CHECK (kind IN ('peak', 'viewpoint', 'waterfall', 'water', 'shelter')),
    name      text NOT NULL DEFAULT '',
    ele       integer,
    source_id text NOT NULL UNIQUE,
    geom      geometry(Point, 4326) NOT NULL
);
CREATE INDEX pois_geom_idx ON pois USING gist (geom);

-- +goose Down
DROP TABLE pois;
