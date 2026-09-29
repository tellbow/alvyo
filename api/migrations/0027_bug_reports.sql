-- +goose Up
-- Bug reports from the website and the app, each opened as a GitHub issue;
-- the screenshot stays here (the repository's issues link to it) and goes
-- with the account.
CREATE TABLE bug_reports (
    id              uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id         uuid NOT NULL REFERENCES users ON DELETE CASCADE,
    created_at      timestamptz NOT NULL DEFAULT now(),
    description     text NOT NULL,
    place           text NOT NULL DEFAULT '',
    version         text NOT NULL DEFAULT '',
    platform        text NOT NULL,
    screenshot      bytea,
    screenshot_type text,
    issue_number    integer
);
CREATE INDEX bug_reports_user_idx ON bug_reports (user_id);

-- +goose Down
DROP TABLE bug_reports;
