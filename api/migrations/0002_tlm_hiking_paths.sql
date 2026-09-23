-- +goose Up
-- Official hiking trail network (swissTLM3D Wanderwege, © swisstopo), loaded by
-- infra/data-import/import-tlm.sh. Kept in LV95 for metric distance queries.
CREATE TABLE tlm_hiking_paths (
    id       bigint PRIMARY KEY,
    category text NOT NULL,  -- Wanderweg | Bergwanderweg | Alpinwanderweg
    geom     geometry(MultiLineString, 2056) NOT NULL
);
CREATE INDEX tlm_hiking_paths_geom_idx ON tlm_hiking_paths USING gist (geom);

-- +goose Down
DROP TABLE tlm_hiking_paths;
