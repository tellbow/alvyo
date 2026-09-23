-- +goose Up
-- Grants give a user (by account) or an e-mail address (an invitation, which
-- applies once someone with that verified address signs in) access to one
-- route or journey. Stage routes follow their journey's grants.
CREATE TYPE grant_role AS ENUM ('viewer', 'editor');

CREATE TABLE grants (
    id         uuid PRIMARY KEY DEFAULT uuidv7(),
    route_id   uuid REFERENCES routes ON DELETE CASCADE,
    journey_id uuid REFERENCES journeys ON DELETE CASCADE,
    user_id    uuid REFERENCES users ON DELETE CASCADE,
    email      citext,
    role       grant_role NOT NULL,
    invited_by uuid REFERENCES users ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (num_nonnulls(route_id, journey_id) = 1),
    CHECK (num_nonnulls(user_id, email) = 1),
    CONSTRAINT grants_target_grantee_key UNIQUE NULLS NOT DISTINCT (route_id, journey_id, user_id, email)
);
CREATE INDEX grants_route_idx ON grants (route_id) WHERE route_id IS NOT NULL;
CREATE INDEX grants_journey_idx ON grants (journey_id) WHERE journey_id IS NOT NULL;
CREATE INDEX grants_user_idx ON grants (user_id) WHERE user_id IS NOT NULL;
CREATE INDEX grants_email_idx ON grants (email) WHERE email IS NOT NULL;

-- +goose Down
DROP TABLE grants;
DROP TYPE grant_role;
