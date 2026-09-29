-- +goose Up
-- Reminders before a journey starts, by e-mail to its owner and the people
-- who come along: what was sent (once per start date), and who turned them off.
CREATE TABLE journey_reminders (
    journey_id uuid NOT NULL REFERENCES journeys ON DELETE CASCADE,
    user_id    uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    kind       text NOT NULL CHECK (kind IN ('book', 'weather', 'start')),
    start_on   date NOT NULL,
    sent_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (journey_id, user_id, kind, start_on)
);

CREATE TABLE journey_reminders_off (
    journey_id uuid NOT NULL REFERENCES journeys ON DELETE CASCADE,
    user_id    uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    PRIMARY KEY (journey_id, user_id)
);

-- +goose Down
DROP TABLE journey_reminders_off;
DROP TABLE journey_reminders;
