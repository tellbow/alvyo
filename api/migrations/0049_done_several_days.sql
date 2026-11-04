-- +goose Up
-- A route or journey can be hiked again: one mark per day.
ALTER TABLE done_marks DROP CONSTRAINT done_marks_key,
    ADD CONSTRAINT done_marks_key UNIQUE NULLS NOT DISTINCT (user_id, route_id, journey_id, done_on);

-- +goose StatementBegin
CREATE OR REPLACE FUNCTION route_done_on(r routes, viewer uuid) RETURNS date LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT max(d.done_on) FROM done_marks d WHERE d.user_id = viewer AND d.route_id = r.id),
        CASE WHEN r.owner_id = viewer THEN (r.hiked_at AT TIME ZONE 'Europe/Zurich')::date END,
        (SELECT max(h.hiked_at AT TIME ZONE 'Europe/Zurich')::date FROM routes h
            WHERE h.planned_route_id = r.id AND h.owner_id = viewer))
$$;
CREATE OR REPLACE FUNCTION journey_done_on(jid uuid, viewer uuid) RETURNS date LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT max(d.done_on) FROM done_marks d WHERE d.user_id = viewer AND d.journey_id = jid),
        (SELECT max(coalesce(s.done_on, s.updated_at::date)) FILTER (WHERE s.status = 'done')
            FROM stages s JOIN journeys j ON j.id = s.journey_id
            WHERE s.journey_id = jid AND (j.owner_id = viewer OR EXISTS (SELECT 1 FROM grants g
                WHERE g.journey_id = jid AND g.user_id = viewer AND g.role = 'editor'))
            HAVING bool_and(s.status <> 'planned')))
$$;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
CREATE OR REPLACE FUNCTION route_done_on(r routes, viewer uuid) RETURNS date LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT d.done_on FROM done_marks d WHERE d.user_id = viewer AND d.route_id = r.id),
        CASE WHEN r.owner_id = viewer THEN (r.hiked_at AT TIME ZONE 'Europe/Zurich')::date END,
        (SELECT max(h.hiked_at AT TIME ZONE 'Europe/Zurich')::date FROM routes h
            WHERE h.planned_route_id = r.id AND h.owner_id = viewer))
$$;
CREATE OR REPLACE FUNCTION journey_done_on(jid uuid, viewer uuid) RETURNS date LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT d.done_on FROM done_marks d WHERE d.user_id = viewer AND d.journey_id = jid),
        (SELECT max(coalesce(s.done_on, s.updated_at::date)) FILTER (WHERE s.status = 'done')
            FROM stages s JOIN journeys j ON j.id = s.journey_id
            WHERE s.journey_id = jid AND (j.owner_id = viewer OR EXISTS (SELECT 1 FROM grants g
                WHERE g.journey_id = jid AND g.user_id = viewer AND g.role = 'editor'))
            HAVING bool_and(s.status <> 'planned')))
$$;
-- +goose StatementEnd
-- The latest mark of each stays.
DELETE FROM done_marks a USING done_marks b
    WHERE a.user_id = b.user_id AND a.route_id IS NOT DISTINCT FROM b.route_id
    AND a.journey_id IS NOT DISTINCT FROM b.journey_id AND a.done_on < b.done_on;
ALTER TABLE done_marks DROP CONSTRAINT done_marks_key,
    ADD CONSTRAINT done_marks_key UNIQUE NULLS NOT DISTINCT (user_id, route_id, journey_id);
