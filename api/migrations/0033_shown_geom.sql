-- +goose Up
-- The line others see, kept with the route so that discovery filters and
-- sorts by it: searching on the whole line of a recorded hike would tell,
-- view by view, where its hidden start and end lie. NULL when nothing is
-- left. A change to shown_line needs an UPDATE of this column.
ALTER TABLE routes ADD COLUMN shown_geom geometry
	GENERATED ALWAYS AS (CASE WHEN hiked_at IS NULL THEN geom ELSE shown_line(geom) END) STORED;
DROP INDEX routes_discover_idx;
CREATE INDEX routes_discover_idx ON routes USING gist (shown_geom) WHERE visibility = 'public' AND journey_id IS NULL;

-- +goose Down
DROP INDEX routes_discover_idx;
ALTER TABLE routes DROP COLUMN shown_geom;
CREATE INDEX routes_discover_idx ON routes USING gist (geom) WHERE visibility = 'public' AND journey_id IS NULL;
