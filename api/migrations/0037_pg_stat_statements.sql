-- +goose Up
-- Time per query, to find the slow ones; collects only where the server
-- preloads it (infra/postgis/Dockerfile).
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- +goose Down
DROP EXTENSION IF EXISTS pg_stat_statements;
