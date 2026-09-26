-- +goose Up
-- Deleting a route clears planned_route_id of the hikes that followed it:
-- without an index every deleted route (each stage of a deleted journey,
-- each route of a deleted account) reads the whole routes table.
CREATE INDEX routes_planned_idx ON routes (planned_route_id) WHERE planned_route_id IS NOT NULL;

-- +goose Down
DROP INDEX routes_planned_idx;
