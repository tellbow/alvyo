-- +goose Up
-- Tags are the owner's quick labels («Winter», «mit Kindern»), stored as
-- typed; compared without case. Stage routes use their journey's tags.
ALTER TABLE routes ADD COLUMN tags text[] NOT NULL DEFAULT '{}';
ALTER TABLE journeys ADD COLUMN tags text[] NOT NULL DEFAULT '{}';
ALTER TABLE collections ADD COLUMN tags text[] NOT NULL DEFAULT '{}';

-- lower_tags(tags) && $1 finds items with any of the (lower-case) tags $1.
-- +goose StatementBegin
CREATE FUNCTION lower_tags(tags text[]) RETURNS text[]
    LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
    AS $$ SELECT coalesce(array_agg(lower(t)), '{}') FROM unnest(tags) t $$;
-- +goose StatementEnd
CREATE INDEX routes_tags_idx ON routes USING gin (lower_tags(tags));
CREATE INDEX journeys_tags_idx ON journeys USING gin (lower_tags(tags));
CREATE INDEX collections_tags_idx ON collections USING gin (lower_tags(tags));

-- +goose Down
DROP INDEX collections_tags_idx;
DROP INDEX journeys_tags_idx;
DROP INDEX routes_tags_idx;
DROP FUNCTION lower_tags;
ALTER TABLE collections DROP COLUMN tags;
ALTER TABLE journeys DROP COLUMN tags;
ALTER TABLE routes DROP COLUMN tags;
