-- +goose Up
-- Deleting an account, a route, a comment or a photo sets these to NULL;
-- without an index each delete reads the whole table.
CREATE INDEX routes_content_by_idx ON routes (content_by) WHERE content_by IS NOT NULL;
CREATE INDEX route_revisions_saved_by_idx ON route_revisions (saved_by) WHERE saved_by IS NOT NULL;
CREATE INDEX reports_route_idx ON reports (route_id) WHERE route_id IS NOT NULL;
CREATE INDEX reports_journey_idx ON reports (journey_id) WHERE journey_id IS NOT NULL;
CREATE INDEX reports_comment_idx ON reports (comment_id) WHERE comment_id IS NOT NULL;
CREATE INDEX reports_photo_idx ON reports (photo_id) WHERE photo_id IS NOT NULL;
CREATE INDEX reports_user_idx ON reports (user_id) WHERE user_id IS NOT NULL;
CREATE INDEX live_shares_route_idx ON live_shares (route_id) WHERE route_id IS NOT NULL;

-- +goose Down
DROP INDEX live_shares_route_idx;
DROP INDEX reports_user_idx;
DROP INDEX reports_photo_idx;
DROP INDEX reports_comment_idx;
DROP INDEX reports_journey_idx;
DROP INDEX reports_route_idx;
DROP INDEX route_revisions_saved_by_idx;
DROP INDEX routes_content_by_idx;
