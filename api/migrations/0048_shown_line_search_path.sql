-- +goose Up
-- pg_restore runs with an empty search_path, so ST_DumpPoints in
-- shown_line was not found and routes (its generated column) was not
-- restored from a dump at all.
ALTER FUNCTION shown_line(geometry) SET search_path = public;

-- +goose Down
ALTER FUNCTION shown_line(geometry) RESET search_path;
