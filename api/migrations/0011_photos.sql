-- +goose Up
-- Photos of routes (not stage routes) and journeys. Files live on disk
-- (ALVYO_PHOTOS_DIR); geom is set only when the photo was taken along the
-- route (its EXIF position is never stored otherwise).
CREATE TABLE photos (
    id          uuid PRIMARY KEY DEFAULT uuidv7(),
    uploader_id uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    route_id    uuid REFERENCES routes ON DELETE CASCADE,
    journey_id  uuid REFERENCES journeys ON DELETE CASCADE,
    caption     text NOT NULL DEFAULT '' CHECK (length(caption) <= 500),
    width       integer NOT NULL,
    height      integer NOT NULL,
    bytes       integer NOT NULL, -- stored size of all versions
    taken_at    timestamptz,
    geom        geometry(Point, 4326),
    position    integer NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT photos_one_target CHECK (num_nonnulls(route_id, journey_id) = 1)
);
CREATE INDEX photos_route_idx ON photos (route_id, position) WHERE route_id IS NOT NULL;
CREATE INDEX photos_journey_idx ON photos (journey_id, position) WHERE journey_id IS NOT NULL;
CREATE INDEX photos_uploader_idx ON photos (uploader_id);

-- Deleted photos, also by cascade (route, journey or account deleted), whose
-- files the API still has to remove.
CREATE TABLE photo_trash (
    id         uuid PRIMARY KEY,
    deleted_at timestamptz NOT NULL DEFAULT now()
);
-- +goose StatementBegin
CREATE FUNCTION photo_to_trash() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO photo_trash (id) VALUES (OLD.id) ON CONFLICT DO NOTHING;
    RETURN OLD;
END
$$;
-- +goose StatementEnd
CREATE TRIGGER photos_to_trash AFTER DELETE ON photos FOR EACH ROW EXECUTE FUNCTION photo_to_trash();

-- Photos can be reported too.
ALTER TABLE reports DROP CONSTRAINT reports_kind_check;
ALTER TABLE reports ADD CONSTRAINT reports_kind_check CHECK (kind IN ('route', 'journey', 'comment', 'user', 'photo'));
ALTER TABLE reports ADD COLUMN photo_id uuid REFERENCES photos ON DELETE SET NULL;

-- +goose Down
ALTER TABLE reports DROP COLUMN photo_id;
DELETE FROM reports WHERE kind = 'photo';
ALTER TABLE reports DROP CONSTRAINT reports_kind_check;
ALTER TABLE reports ADD CONSTRAINT reports_kind_check CHECK (kind IN ('route', 'journey', 'comment', 'user'));
DROP TRIGGER photos_to_trash ON photos;
DROP FUNCTION photo_to_trash();
DROP TABLE photo_trash;
DROP TABLE photos;
