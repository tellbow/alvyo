-- +goose Up
-- Items also go when their route, journey or account is deleted (ON DELETE
-- CASCADE), so the positions are closed up after every delete, not only
-- after removing an item. Per statement: one delete can take several items
-- of a collection (an account with many routes), and shifting row by row
-- would then depend on the order.
-- +goose StatementBegin
CREATE FUNCTION collection_items_renumber() RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
    UPDATE collection_items c SET position = r.n - 1
    FROM (SELECT id, row_number() OVER (PARTITION BY collection_id ORDER BY position) AS n
          FROM collection_items
          WHERE collection_id IN (SELECT collection_id FROM gone)) r
    WHERE c.id = r.id AND c.position <> r.n - 1;
    RETURN NULL;
END $$;
-- +goose StatementEnd
CREATE TRIGGER collection_items_renumber AFTER DELETE ON collection_items
    REFERENCING OLD TABLE AS gone
    FOR EACH STATEMENT EXECUTE FUNCTION collection_items_renumber();

-- Collections that already have gaps.
UPDATE collection_items c SET position = r.n - 1
FROM (SELECT id, row_number() OVER (PARTITION BY collection_id ORDER BY position) AS n
      FROM collection_items) r
WHERE c.id = r.id AND c.position <> r.n - 1;

-- +goose Down
DROP TRIGGER collection_items_renumber ON collection_items;
DROP FUNCTION collection_items_renumber();
