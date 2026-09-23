-- +goose Up
-- Discovery searches public routes (not journey stages) in the map view,
-- nearest to its centre first.
CREATE INDEX routes_discover_idx ON routes USING gist (geom) WHERE visibility = 'public' AND journey_id IS NULL;
-- Journeys are found through their stage routes.
CREATE INDEX routes_stage_geom_idx ON routes USING gist (geom) WHERE journey_id IS NOT NULL;

-- +goose Down
DROP INDEX routes_stage_geom_idx;
DROP INDEX routes_discover_idx;
