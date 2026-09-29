-- +goose Up
-- More kinds along the way: fire places, picnic spots, restaurants and
-- cafés, toilets and cable car stations.
ALTER TABLE pois DROP CONSTRAINT pois_kind_check;
ALTER TABLE pois ADD CONSTRAINT pois_kind_check CHECK (kind IN (
    'peak', 'viewpoint', 'waterfall', 'water', 'shelter',
    'firepit', 'picnic', 'restaurant', 'toilets', 'cablecar'));

-- +goose Down
DELETE FROM pois WHERE kind IN ('firepit', 'picnic', 'restaurant', 'toilets', 'cablecar');
ALTER TABLE pois DROP CONSTRAINT pois_kind_check;
ALTER TABLE pois ADD CONSTRAINT pois_kind_check CHECK (kind IN ('peak', 'viewpoint', 'waterfall', 'water', 'shelter'));
