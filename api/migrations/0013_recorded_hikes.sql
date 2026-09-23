-- +goose Up
-- Hikes recorded with the app are routes too (source 'recorded', source_ref
-- the app's recording id): when they were hiked, how long they took, and the
-- planned route that was followed.
ALTER TABLE routes
    DROP CONSTRAINT routes_source_check,
    ADD CONSTRAINT routes_source_check CHECK (source IN ('gpx', 'kml', 'tcx', 'fit', 'komoot', 'recorded')),
    ADD COLUMN hiked_at         timestamptz,
    ADD COLUMN hiked_s          integer CHECK (hiked_s >= 0),
    ADD COLUMN planned_route_id uuid REFERENCES routes (id) ON DELETE SET NULL;

-- +goose Down
DELETE FROM routes WHERE source = 'recorded';
ALTER TABLE routes
    DROP COLUMN planned_route_id,
    DROP COLUMN hiked_s,
    DROP COLUMN hiked_at,
    DROP CONSTRAINT routes_source_check,
    ADD CONSTRAINT routes_source_check CHECK (source IN ('gpx', 'kml', 'tcx', 'fit', 'komoot'));
