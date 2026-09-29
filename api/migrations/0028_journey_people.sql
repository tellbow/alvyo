-- +goose Up
-- The people who come along on a journey: grants marked along (they see it
-- as viewers at least), and the stages each is on.
ALTER TABLE grants ADD COLUMN along boolean NOT NULL DEFAULT false;

CREATE TABLE stage_people (
    stage_id uuid NOT NULL REFERENCES stages ON DELETE CASCADE,
    grant_id uuid NOT NULL REFERENCES grants ON DELETE CASCADE,
    PRIMARY KEY (stage_id, grant_id)
);
CREATE INDEX stage_people_grant_idx ON stage_people (grant_id);

-- +goose Down
DROP TABLE stage_people;
ALTER TABLE grants DROP COLUMN along;
