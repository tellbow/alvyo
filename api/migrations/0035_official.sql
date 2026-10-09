-- +goose Up
-- The official hiking routes of Wanderland Schweiz (ASTRA / SchweizMobil,
-- ch.astra.wanderland, open use with source). infra/data-import/
-- import-wanderland.sh replaces the contents of wanderland_routes and
-- wanderland_stages in one transaction and sets imported_at; the API then
-- turns them into public routes and journeys of the account «wanderland».
CREATE TABLE wanderland_routes (
    nr         text PRIMARY KEY,
    name       text NOT NULL,
    kind       text NOT NULL, -- national, regional, local, handicap
    start_name text NOT NULL DEFAULT '',
    end_name   text NOT NULL DEFAULT '',
    geom       geometry(MultiLineString, 4326)
);
CREATE TABLE wanderland_stages (
    nr         text NOT NULL,
    stage      integer NOT NULL,
    start_name text NOT NULL DEFAULT '',
    end_name   text NOT NULL DEFAULT '',
    geom       geometry(MultiLineString, 4326) NOT NULL,
    PRIMARY KEY (nr, stage)
);
-- The pieces ridden, not walked (boats, a bus, cable cars): stages are cut
-- there into parts with a transfer between them.
CREATE TABLE wanderland_transport (
    mode text NOT NULL, -- boat, Bus, Luftseilbahn, Zahnrad- und Standseilbahn
    geom geometry(MultiLineString, 4326) NOT NULL
);
CREATE TABLE wanderland_import (
    one         boolean PRIMARY KEY DEFAULT true CHECK (one),
    imported_at timestamptz NOT NULL,
    synced_at   timestamptz
);

-- A Wanderland route as an Alvyo route (one stage) or journey (several),
-- with a hash of its data so that a sync skips what did not change.
CREATE TABLE official (
    nr         text PRIMARY KEY,
    kind       text NOT NULL CHECK (kind IN ('national', 'regional', 'local', 'handicap')),
    route_id   uuid UNIQUE REFERENCES routes ON DELETE CASCADE,
    journey_id uuid UNIQUE REFERENCES journeys ON DELETE CASCADE,
    hash       text NOT NULL,
    CHECK ((route_id IS NULL) <> (journey_id IS NULL))
);

-- The account that owns them: no password and an address that receives no
-- mail (.invalid), so no one can log in.
INSERT INTO users (email, username, display_name)
VALUES ('wanderland@alvyo.invalid', 'wanderland', 'Wanderland Schweiz');

-- +goose Down
DELETE FROM users WHERE username = 'wanderland';
DROP TABLE official;
DROP TABLE wanderland_import;
DROP TABLE wanderland_transport;
DROP TABLE wanderland_stages;
DROP TABLE wanderland_routes;
