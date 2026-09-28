-- +goose Up
-- The way to and from a journey from anywhere, not only from a home: a
-- place found by the search, with its name.
ALTER TABLE journey_travel
    ALTER COLUMN home_id DROP NOT NULL,
    ADD COLUMN place_name text CHECK (length(place_name) BETWEEN 1 AND 60),
    ADD COLUMN place_lon double precision CHECK (place_lon BETWEEN -180 AND 180),
    ADD COLUMN place_lat double precision CHECK (place_lat BETWEEN -90 AND 90),
    ADD CONSTRAINT journey_travel_from CHECK (
        num_nonnulls(home_id, place_lon) = 1
        AND num_nonnulls(place_name, place_lon, place_lat) IN (0, 3));

-- The same for a route: to its start and back from its end.
CREATE TABLE route_travel (
    user_id    uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    route_id   uuid NOT NULL REFERENCES routes ON DELETE CASCADE,
    direction  text NOT NULL CHECK (direction IN ('to', 'back')),
    home_id    uuid REFERENCES homes ON DELETE CASCADE,
    place_name text CHECK (length(place_name) BETWEEN 1 AND 60),
    place_lon  double precision CHECK (place_lon BETWEEN -180 AND 180),
    place_lat  double precision CHECK (place_lat BETWEEN -90 AND 90),
    at_time    text NOT NULL CHECK (at_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
    arrive     boolean NOT NULL DEFAULT false,
    PRIMARY KEY (user_id, route_id, direction),
    CHECK (num_nonnulls(home_id, place_lon) = 1
        AND num_nonnulls(place_name, place_lon, place_lat) IN (0, 3))
);

-- +goose Down
DROP TABLE route_travel;
DELETE FROM journey_travel WHERE home_id IS NULL;
ALTER TABLE journey_travel
    DROP CONSTRAINT journey_travel_from,
    DROP COLUMN place_name, DROP COLUMN place_lon, DROP COLUMN place_lat,
    ALTER COLUMN home_id SET NOT NULL;
