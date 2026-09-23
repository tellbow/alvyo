-- +goose Up
-- Where an imported route came from, so that imports can skip what is
-- already there (e.g. a Komoot tour imported before).
ALTER TABLE routes
    ADD COLUMN source     text CHECK (source IN ('gpx', 'kml', 'tcx', 'fit', 'komoot')),
    ADD COLUMN source_ref text CHECK (length(source_ref) <= 100);
CREATE UNIQUE INDEX routes_source_ref_idx ON routes (owner_id, source, source_ref) WHERE source_ref IS NOT NULL;

-- +goose Down
DROP INDEX routes_source_ref_idx;
ALTER TABLE routes DROP COLUMN source, DROP COLUMN source_ref;
