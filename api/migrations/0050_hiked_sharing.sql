-- +goose Up
-- What others may see of what a user has hiked. Off until they choose; the
-- map shows where someone walks, so each has its own choice.
ALTER TABLE users
    ADD COLUMN share_stats text NOT NULL DEFAULT 'nobody' CHECK (share_stats IN ('nobody', 'friends', 'public')),
    ADD COLUMN share_map text NOT NULL DEFAULT 'nobody' CHECK (share_map IN ('nobody', 'friends', 'public')),
    ADD COLUMN share_achievements text NOT NULL DEFAULT 'nobody' CHECK (share_achievements IN ('nobody', 'friends', 'public'));

-- +goose Down
ALTER TABLE users DROP COLUMN share_stats, DROP COLUMN share_map, DROP COLUMN share_achievements;
