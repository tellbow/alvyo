-- +goose Up
-- A collection is an ordered list of routes and journeys ("Alpine passes",
-- "Wishlist 2027"). It never grants access to its items: every viewer sees
-- only the items they may open anyway.
CREATE TABLE collections (
    id          uuid PRIMARY KEY DEFAULT uuidv7(),
    owner_id    uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    title       text NOT NULL CHECK (length(title) BETWEEN 1 AND 120),
    description text NOT NULL DEFAULT '' CHECK (length(description) <= 5000),
    visibility  visibility NOT NULL DEFAULT 'private',
    share_token text UNIQUE,
    version     integer NOT NULL DEFAULT 1,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX collections_owner_idx ON collections (owner_id, updated_at DESC);

CREATE TABLE collection_items (
    id            uuid PRIMARY KEY DEFAULT uuidv7(),
    collection_id uuid NOT NULL REFERENCES collections ON DELETE CASCADE,
    position      integer NOT NULL,
    route_id      uuid REFERENCES routes ON DELETE CASCADE,
    journey_id    uuid REFERENCES journeys ON DELETE CASCADE,
    note          text NOT NULL DEFAULT '' CHECK (length(note) <= 1000),
    added_by      uuid REFERENCES users ON DELETE SET NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    CHECK (num_nonnulls(route_id, journey_id) = 1),
    CONSTRAINT collection_items_once UNIQUE NULLS NOT DISTINCT (collection_id, route_id, journey_id),
    CONSTRAINT collection_items_position_key UNIQUE (collection_id, position) DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX collection_items_route_idx ON collection_items (route_id) WHERE route_id IS NOT NULL;
CREATE INDEX collection_items_journey_idx ON collection_items (journey_id) WHERE journey_id IS NOT NULL;

-- Collections are shared like routes and journeys.
ALTER TABLE grants ADD COLUMN collection_id uuid REFERENCES collections ON DELETE CASCADE;
ALTER TABLE grants DROP CONSTRAINT grants_check;
ALTER TABLE grants ADD CONSTRAINT grants_one_target CHECK (num_nonnulls(route_id, journey_id, collection_id) = 1);
ALTER TABLE grants DROP CONSTRAINT grants_target_grantee_key;
ALTER TABLE grants ADD CONSTRAINT grants_target_grantee_key
    UNIQUE NULLS NOT DISTINCT (route_id, journey_id, collection_id, user_id, email);
CREATE INDEX grants_collection_idx ON grants (collection_id) WHERE collection_id IS NOT NULL;

-- +goose Down
DELETE FROM grants WHERE collection_id IS NOT NULL;
DROP INDEX grants_collection_idx;
ALTER TABLE grants DROP CONSTRAINT grants_target_grantee_key;
ALTER TABLE grants ADD CONSTRAINT grants_target_grantee_key
    UNIQUE NULLS NOT DISTINCT (route_id, journey_id, user_id, email);
ALTER TABLE grants DROP CONSTRAINT grants_one_target;
ALTER TABLE grants DROP COLUMN collection_id;
ALTER TABLE grants ADD CONSTRAINT grants_check CHECK (num_nonnulls(route_id, journey_id) = 1);
DROP TABLE collection_items;
DROP TABLE collections;
