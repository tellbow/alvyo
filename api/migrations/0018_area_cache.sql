-- +goose Up
-- The protected areas a line crosses, as geo.admin answered for it (keyed by
-- a hash of the simplified line); kept for 30 days.
CREATE TABLE area_cache (
    line_key   text PRIMARY KEY,
    areas      jsonb NOT NULL,
    fetched_at timestamptz NOT NULL DEFAULT now()
);

-- +goose Down
DROP TABLE area_cache;
