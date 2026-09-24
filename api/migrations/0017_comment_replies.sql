-- +goose Up
-- Replies to a comment (one level: a reply's parent is a comment on the same
-- item without a parent) and edits by the author.
ALTER TABLE comments
    ADD COLUMN parent_id uuid REFERENCES comments ON DELETE CASCADE,
    ADD COLUMN edited_at timestamptz;
CREATE INDEX comments_parent_idx ON comments (parent_id) WHERE parent_id IS NOT NULL;

-- +goose Down
DELETE FROM comments WHERE parent_id IS NOT NULL;
ALTER TABLE comments DROP COLUMN edited_at, DROP COLUMN parent_id;
