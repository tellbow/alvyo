-- +goose Up
-- Hiked: routes and journeys a user marks as done (theirs or others'), with
-- the day.
CREATE TABLE done_marks (
    user_id    uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    route_id   uuid REFERENCES routes ON DELETE CASCADE,
    journey_id uuid REFERENCES journeys ON DELETE CASCADE,
    done_on    date NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT done_marks_one_target CHECK (num_nonnulls(route_id, journey_id) = 1),
    CONSTRAINT done_marks_key UNIQUE NULLS NOT DISTINCT (user_id, route_id, journey_id)
);
CREATE INDEX done_marks_route_idx ON done_marks (route_id) WHERE route_id IS NOT NULL;
CREATE INDEX done_marks_journey_idx ON done_marks (journey_id) WHERE journey_id IS NOT NULL;

-- The day viewer hiked route r: their mark, else their recording of it, or
-- of a hike they recorded with it as the plan; null if not hiked.
-- +goose StatementBegin
CREATE FUNCTION route_done_on(r routes, viewer uuid) RETURNS date LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT d.done_on FROM done_marks d WHERE d.user_id = viewer AND d.route_id = r.id),
        CASE WHEN r.owner_id = viewer THEN (r.hiked_at AT TIME ZONE 'Europe/Zurich')::date END,
        (SELECT max(h.hiked_at AT TIME ZONE 'Europe/Zurich')::date FROM routes h
            WHERE h.planned_route_id = r.id AND h.owner_id = viewer))
$$;
-- +goose StatementEnd

-- The day viewer finished journey jid: their mark, else, for its owner and
-- editors, the last day a stage was ticked off once none is left planned
-- (and one was hiked); null if not.
-- +goose StatementBegin
CREATE FUNCTION journey_done_on(jid uuid, viewer uuid) RETURNS date LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT d.done_on FROM done_marks d WHERE d.user_id = viewer AND d.journey_id = jid),
        (SELECT max(coalesce(s.done_on, s.updated_at::date)) FILTER (WHERE s.status = 'done')
            FROM stages s JOIN journeys j ON j.id = s.journey_id
            WHERE s.journey_id = jid AND (j.owner_id = viewer OR EXISTS (SELECT 1 FROM grants g
                WHERE g.journey_id = jid AND g.user_id = viewer AND g.role = 'editor'))
            HAVING bool_and(s.status <> 'planned')))
$$;
-- +goose StatementEnd

-- +goose Down
DROP FUNCTION journey_done_on(uuid, uuid);
DROP FUNCTION route_done_on(routes, uuid);
DROP TABLE done_marks;
