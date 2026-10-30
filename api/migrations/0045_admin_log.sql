-- +goose Up
-- The admin portal's «Verlauf» (feedback issues 70, 72): every action, and
-- for those that can be undone the rows as they were before it.
CREATE TABLE admin_log (
    id          uuid PRIMARY KEY DEFAULT uuidv7(),
    at          timestamptz NOT NULL DEFAULT now(),
    actor_id    uuid REFERENCES users ON DELETE SET NULL,
    area        text NOT NULL CHECK (area IN ('meldungen', 'nutzer', 'inhalte')),
    title       text NOT NULL,
    target_kind text NOT NULL,
    target_id   uuid NOT NULL,
    -- [{"table": …, "id": …, "set": {column: value}}]; null: not undoable
    undo        jsonb,
    undone_at   timestamptz,
    undone_by   uuid REFERENCES users ON DELETE SET NULL
);
CREATE INDEX admin_log_at_idx ON admin_log (at DESC);
CREATE INDEX admin_log_target_idx ON admin_log (target_id, at DESC);
-- +goose Down
DROP TABLE admin_log;
