-- +goose Up
-- Screenshots of bug reports are committed to the feedback repository
-- (since 1.1.0); those kept here were moved there on 2026-10-15.
ALTER TABLE bug_reports DROP COLUMN screenshot, DROP COLUMN screenshot_type;

-- +goose Down
ALTER TABLE bug_reports ADD COLUMN screenshot bytea, ADD COLUMN screenshot_type text;
