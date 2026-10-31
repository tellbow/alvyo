-- +goose Up
-- A profile picture: one square JPEG on disk next to the photos, named by
-- this id. A new picture gets a new id, so its URL can be cached for good.
ALTER TABLE users ADD COLUMN avatar uuid;

-- A replaced or removed picture, also with its account, goes to the photo
-- trash, whose sweep removes the file.
-- +goose StatementBegin
CREATE FUNCTION avatar_to_trash() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO photo_trash (id) VALUES (OLD.avatar) ON CONFLICT DO NOTHING;
    RETURN OLD;
END
$$;
-- +goose StatementEnd
CREATE TRIGGER avatar_replaced AFTER UPDATE OF avatar ON users FOR EACH ROW
    WHEN (OLD.avatar IS NOT NULL AND OLD.avatar IS DISTINCT FROM NEW.avatar)
    EXECUTE FUNCTION avatar_to_trash();
CREATE TRIGGER avatar_deleted AFTER DELETE ON users FOR EACH ROW
    WHEN (OLD.avatar IS NOT NULL)
    EXECUTE FUNCTION avatar_to_trash();

-- +goose Down
DROP TRIGGER avatar_deleted ON users;
DROP TRIGGER avatar_replaced ON users;
DROP FUNCTION avatar_to_trash();
ALTER TABLE users DROP COLUMN avatar;
