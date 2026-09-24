-- +goose Up
-- Websites of huts and accommodation (OSM website or contact:website), to
-- check opening times and book: OSM rarely knows either.
ALTER TABLE places ADD COLUMN website text NOT NULL DEFAULT '';

-- +goose Down
ALTER TABLE places DROP COLUMN website;
