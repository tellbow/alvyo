-- +goose Up
-- Friends see one's hikes (marked as hiked or recorded) in their news,
-- unless switched off.
ALTER TABLE users ADD COLUMN share_hikes boolean NOT NULL DEFAULT true;
CREATE INDEX done_marks_user_idx ON done_marks (user_id, created_at);

-- +goose Down
DROP INDEX done_marks_user_idx;
ALTER TABLE users DROP COLUMN share_hikes;
