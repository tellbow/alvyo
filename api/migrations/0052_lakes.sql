-- +goose Up
-- Lakes, cut out of the areas of «Wie weit komme ich?»: OpenStreetMap's
-- water areas of lakes and reservoirs from 0.1 km², in LV95 like the areas'
-- outlines. Loaded by infra/data-import/import-places.sh.
CREATE TABLE lakes (
    source_id text PRIMARY KEY,
    geom      geometry(MultiPolygon, 2056) NOT NULL
);
CREATE INDEX lakes_geom_idx ON lakes USING gist (geom);

-- +goose Down
DROP TABLE lakes;
