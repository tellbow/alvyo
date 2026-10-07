-- +goose Up
-- Rain on the map: pictures of MeteoSwiss's radar (the last hour) and of the
-- ICON-CH1 forecast (the next hours), made by the weather-precip job
-- (infra/data-import/weather-precip.py). bounds: the picture's corners.
CREATE TABLE precip_frames (
    kind       text NOT NULL CHECK (kind IN ('radar', 'forecast')),
    valid_at   timestamptz NOT NULL,
    run_at     timestamptz,
    png        bytea NOT NULL,
    west       double precision NOT NULL,
    south      double precision NOT NULL,
    east       double precision NOT NULL,
    north      double precision NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (kind, valid_at)
);

-- +goose Down
DROP TABLE precip_frames;
