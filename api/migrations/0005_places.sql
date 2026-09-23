-- +goose Up
-- Reference places for stage starts and ends: public transport stops (BAV,
-- Didok numbers) and huts and accommodation (OpenStreetMap). Loaded by
-- infra/data-import/import-places.sh, which upserts by (source, source_id) so
-- stages keep their references across refreshes.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE places (
    id        uuid PRIMARY KEY DEFAULT uuidv7(),
    kind      text NOT NULL CHECK (kind IN ('pt_stop', 'hut', 'hotel', 'campsite')),
    name      text NOT NULL,
    -- Transport modes of a stop ("Bus", "Zug" …) or the OSM tourism value.
    detail    text NOT NULL DEFAULT '',
    source    text NOT NULL CHECK (source IN ('didok', 'osm')),
    -- Didok number (8509411 = Sargans) or OSM n123 / w456 / r789.
    source_id text NOT NULL,
    geom      geometry(Point, 4326) NOT NULL,
    UNIQUE (source, source_id)
);
CREATE INDEX places_geom_idx ON places USING gist (geom); -- nearest first (<->)
CREATE INDEX places_geog_idx ON places USING gist ((geom::geography)); -- ST_DWithin in metres
CREATE INDEX places_name_idx ON places USING gin (name gin_trgm_ops);

-- Without an explicit start or end place, the nearest stop or hut to the
-- route end is suggested when reading the journey.
ALTER TABLE stages
    ADD COLUMN start_place_id       uuid REFERENCES places ON DELETE SET NULL,
    ADD COLUMN end_place_id         uuid REFERENCES places ON DELETE SET NULL,
    -- Where the hiker sleeps after the stage.
    ADD COLUMN accommodation        text NOT NULL DEFAULT '' CHECK (length(accommodation) <= 200),
    ADD COLUMN accommodation_booked boolean NOT NULL DEFAULT false;

-- +goose Down
ALTER TABLE stages
    DROP COLUMN start_place_id,
    DROP COLUMN end_place_id,
    DROP COLUMN accommodation,
    DROP COLUMN accommodation_booked;
DROP TABLE places;
