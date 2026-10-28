-- +goose Up
-- «Nicht vorschlagen»: people the user does not want suggested as friends.
CREATE TABLE suggestion_dismissals (
    user_id      uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    dismissed_id uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    created_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, dismissed_id)
);
CREATE INDEX suggestion_dismissals_dismissed_idx ON suggestion_dismissals (dismissed_id);
-- +goose Down
DROP TABLE suggestion_dismissals;
