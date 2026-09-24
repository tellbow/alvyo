-- +goose Up
-- Stage changes carry the version they are based on, so two editors of one
-- stage do not overwrite each other unnoticed.
ALTER TABLE stages ADD COLUMN version integer NOT NULL DEFAULT 1;

-- +goose Down
ALTER TABLE stages DROP COLUMN version;
