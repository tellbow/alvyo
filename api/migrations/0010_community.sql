-- +goose Up
-- Community: likes, comments, follows, blocks, reports and e-mail
-- notification settings.

ALTER TABLE users
    ADD COLUMN notify_comments boolean NOT NULL DEFAULT true,
    ADD COLUMN notify_follows  boolean NOT NULL DEFAULT true;

-- Owners can switch comments off. published_at is when an item first became
-- public; it orders the feed.
ALTER TABLE routes
    ADD COLUMN comments_enabled boolean NOT NULL DEFAULT true,
    ADD COLUMN published_at     timestamptz;
ALTER TABLE journeys
    ADD COLUMN comments_enabled boolean NOT NULL DEFAULT true,
    ADD COLUMN published_at     timestamptz;
UPDATE routes SET published_at = updated_at WHERE visibility = 'public';
UPDATE journeys SET published_at = updated_at WHERE visibility = 'public';

-- +goose StatementBegin
CREATE FUNCTION set_published_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.visibility = 'public' AND NEW.published_at IS NULL THEN
        NEW.published_at := now();
    END IF;
    RETURN NEW;
END
$$;
-- +goose StatementEnd
CREATE TRIGGER routes_published_at BEFORE INSERT OR UPDATE OF visibility ON routes
    FOR EACH ROW EXECUTE FUNCTION set_published_at();
CREATE TRIGGER journeys_published_at BEFORE INSERT OR UPDATE OF visibility ON journeys
    FOR EACH ROW EXECUTE FUNCTION set_published_at();
CREATE INDEX routes_published_idx ON routes (owner_id, published_at DESC)
    WHERE visibility = 'public' AND journey_id IS NULL;
CREATE INDEX journeys_published_idx ON journeys (owner_id, published_at DESC) WHERE visibility = 'public';

-- Likes and comments are on a route (not a stage route) or a journey.
CREATE TABLE likes (
    user_id    uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    route_id   uuid REFERENCES routes ON DELETE CASCADE,
    journey_id uuid REFERENCES journeys ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT likes_one_target CHECK (num_nonnulls(route_id, journey_id) = 1),
    CONSTRAINT likes_key UNIQUE NULLS NOT DISTINCT (user_id, route_id, journey_id)
);
CREATE INDEX likes_route_idx ON likes (route_id) WHERE route_id IS NOT NULL;
CREATE INDEX likes_journey_idx ON likes (journey_id) WHERE journey_id IS NOT NULL;

CREATE TABLE comments (
    id         uuid PRIMARY KEY DEFAULT uuidv7(),
    author_id  uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    route_id   uuid REFERENCES routes ON DELETE CASCADE,
    journey_id uuid REFERENCES journeys ON DELETE CASCADE,
    body       text NOT NULL CHECK (length(body) BETWEEN 1 AND 2000),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT comments_one_target CHECK (num_nonnulls(route_id, journey_id) = 1)
);
CREATE INDEX comments_route_idx ON comments (route_id, created_at) WHERE route_id IS NOT NULL;
CREATE INDEX comments_journey_idx ON comments (journey_id, created_at) WHERE journey_id IS NOT NULL;
CREATE INDEX comments_author_idx ON comments (author_id);

CREATE TABLE follows (
    follower_id uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    followed_id uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (follower_id, followed_id),
    CHECK (follower_id <> followed_id)
);
CREATE INDEX follows_followed_idx ON follows (followed_id);

-- A blocked user cannot comment on the blocker's items or follow them, and
-- the blocker no longer sees their comments.
CREATE TABLE blocks (
    blocker_id uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    blocked_id uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (blocker_id, blocked_id),
    CHECK (blocker_id <> blocked_id)
);
CREATE INDEX blocks_blocked_idx ON blocks (blocked_id);

-- Reports go to the moderators. Targets may be deleted later (SET NULL);
-- excerpt keeps what was reported.
CREATE TABLE reports (
    id          uuid PRIMARY KEY DEFAULT uuidv7(),
    reporter_id uuid REFERENCES users ON DELETE SET NULL,
    kind        text NOT NULL CHECK (kind IN ('route', 'journey', 'comment', 'user')),
    target_id   uuid NOT NULL, -- id of the route, journey, comment or user
    route_id    uuid REFERENCES routes ON DELETE SET NULL,
    journey_id  uuid REFERENCES journeys ON DELETE SET NULL,
    comment_id  uuid REFERENCES comments ON DELETE SET NULL,
    user_id     uuid REFERENCES users ON DELETE SET NULL, -- the reported user, or the target's owner/author
    excerpt     text NOT NULL,
    reason      text NOT NULL CHECK (reason IN ('spam', 'offensive', 'dangerous', 'other')),
    note        text NOT NULL DEFAULT '' CHECK (length(note) <= 1000),
    created_at  timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,
    resolved_by uuid REFERENCES users ON DELETE SET NULL,
    resolution  text CHECK (resolution IN ('dismissed', 'removed'))
);
CREATE UNIQUE INDEX reports_open_key ON reports (reporter_id, target_id) WHERE resolved_at IS NULL;
CREATE INDEX reports_open_idx ON reports (created_at) WHERE resolved_at IS NULL;

-- Last notification e-mail per recipient and topic (e.g. comments on one
-- route), to send at most one every 15 minutes.
CREATE TABLE mail_throttle (
    user_id uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    topic   text NOT NULL,
    sent_at timestamptz NOT NULL,
    PRIMARY KEY (user_id, topic)
);

-- +goose Down
DROP TABLE mail_throttle;
DROP TABLE reports;
DROP TABLE blocks;
DROP TABLE follows;
DROP TABLE comments;
DROP TABLE likes;
DROP INDEX journeys_published_idx;
DROP INDEX routes_published_idx;
DROP TRIGGER journeys_published_at ON journeys;
DROP TRIGGER routes_published_at ON routes;
DROP FUNCTION set_published_at();
ALTER TABLE journeys DROP COLUMN comments_enabled, DROP COLUMN published_at;
ALTER TABLE routes DROP COLUMN comments_enabled, DROP COLUMN published_at;
ALTER TABLE users DROP COLUMN notify_comments, DROP COLUMN notify_follows;
