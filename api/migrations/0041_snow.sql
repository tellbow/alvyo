-- +goose Up
-- Snow on the map: Copernicus's daily snow cover as PNG tiles (Web
-- Mercator, only tiles with snow), made by the snow-cover job
-- (infra/data-import/snow-cover.py). One day is kept: the newest.
CREATE TABLE snow_days (
    day        date PRIMARY KEY, -- the day the product is for
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE snow_tiles (
    day date NOT NULL REFERENCES snow_days ON DELETE CASCADE,
    z   smallint NOT NULL,
    x   integer NOT NULL,
    y   integer NOT NULL,
    png bytea NOT NULL,
    PRIMARY KEY (day, z, x, y)
);

-- +goose Down
DROP TABLE snow_tiles;
DROP TABLE snow_days;
