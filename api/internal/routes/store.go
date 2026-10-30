package routes

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Store errors.
var (
	ErrNotFound  = errors.New("route not found")
	ErrVersion   = errors.New("route was changed by someone else")
	ErrDuplicate = errors.New("imported before")
)

// Store reads and writes routes.
type Store struct {
	DB *pgxpool.Pool
}

const summaryColumns = `r.id, u.username, r.title, r.description, r.visibility, r.profile,
	r.distance_m, r.ascent_m, r.descent_m, r.duration_s, r.duration_reverse_s,
	r.ele_min_m, r.ele_max_m, r.sac_grade, r.sac_max, r.version, r.created_at, r.updated_at,
	r.hiked_at, r.hiked_s, r.planned_route_id,
	CASE WHEN r.journey_id IS NULL THEN r.tags ELSE (SELECT j.tags FROM journeys j WHERE j.id = r.journey_id) END`

func scanSummary(row pgx.Row, extra ...any) (Summary, error) {
	var s Summary
	var id uuid.UUID
	var hikedAt *time.Time
	var hikedS *int
	var planned *uuid.UUID
	dest := []any{&id, &s.OwnerUsername, &s.Title, &s.Description, &s.Visibility, &s.Profile,
		&s.Totals.DistanceM, &s.Totals.AscentM, &s.Totals.DescentM, &s.Totals.DurationS, &s.Totals.DurationReverseS,
		&s.Totals.EleMinM, &s.Totals.EleMaxM, &s.Totals.SACGrade, &s.Totals.SACMax, &s.Version, &s.CreatedAt, &s.UpdatedAt,
		&hikedAt, &hikedS, &planned, &s.Tags}
	err := row.Scan(append(dest, extra...)...)
	s.ID = id.String()
	if hikedAt != nil && hikedS != nil {
		s.Hike = &Hike{At: *hikedAt, DurationS: *hikedS}
		if planned != nil {
			s.Hike.PlannedRouteID = planned.String()
		}
	}
	return s, err
}

// Create stores a new route owned by ownerID.
func (s *Store) Create(ctx context.Context, ownerID uuid.UUID, m Meta, c Content) (Route, error) {
	return s.create(ctx, s.DB, ownerID, nil, m, c)
}

// Querier is a pool or a transaction.
type Querier interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// CreateInJourney stores a stage route of a journey (inside tx).
func (s *Store) CreateInJourney(ctx context.Context, tx Querier, ownerID, journeyID uuid.UUID, title string, c Content) (uuid.UUID, error) {
	r, err := s.create(ctx, tx, ownerID, &journeyID, Meta{Title: title, Visibility: "private"}, c)
	if err != nil {
		return uuid.Nil, err
	}
	return uuid.MustParse(r.ID), nil
}

func (s *Store) create(ctx context.Context, q Querier, ownerID uuid.UUID, journeyID *uuid.UUID, m Meta, c Content) (Route, error) {
	a, err := assemble(c)
	if err != nil {
		return Route{}, err
	}
	anchors, legs, err := encode(c.Anchors, a.legs)
	if err != nil {
		return Route{}, err
	}
	t := a.totals
	var id uuid.UUID
	err = q.QueryRow(ctx, `
		INSERT INTO routes (owner_id, title, description, visibility, profile, anchors, legs, geom,
			distance_m, ascent_m, descent_m, duration_s, duration_reverse_s, ele_min_m, ele_max_m, sac_grade, sac_max,
			share_token, journey_id, tags)
		VALUES ($1, $2, $3, $4::visibility, $5, $6, $7, ST_GeomFromText($8, 4326),
			$9, $10, $11, $12, $13, $14, $15, $16, $17,
			CASE WHEN $4::visibility = 'unlisted' THEN $18 END, $19, coalesce($20::text[], '{}'))
		RETURNING id`,
		ownerID, m.Title, m.Description, m.Visibility, c.Profile, anchors, legs, a.wkt,
		round(t.DistanceM), round(t.AscentM), round(t.DescentM), t.DurationS, t.DurationReverseS,
		round(t.EleMinM), round(t.EleMaxM), t.SACGrade, t.SACMax, NewShareToken(), journeyID, m.Tags,
	).Scan(&id)
	if err != nil {
		return Route{}, fmt.Errorf("routes: create: %w", err)
	}
	if journeyID != nil {
		return Route{Summary: Summary{ID: id.String()}}, nil // caller is inside a transaction
	}
	return s.Get(ctx, id)
}

// Get loads a route with its planner state.
func (s *Store) Get(ctx context.Context, id uuid.UUID) (Route, error) {
	var r Route
	var owner uuid.UUID
	var anchors, legs []byte
	var token *string
	var journey *uuid.UUID
	row := s.DB.QueryRow(ctx, `SELECT `+summaryColumns+`, r.owner_id, r.anchors, r.legs, r.share_token, r.journey_id
		FROM routes r JOIN users u ON u.id = r.owner_id WHERE r.id = $1`, id)
	sum, err := scanSummary(row, &owner, &anchors, &legs, &token, &journey)
	if errors.Is(err, pgx.ErrNoRows) {
		return Route{}, ErrNotFound
	}
	if err != nil {
		return Route{}, fmt.Errorf("routes: get: %w", err)
	}
	r.Summary = sum
	r.OwnerID = owner.String()
	if token != nil {
		r.ShareToken = *token
	}
	if journey != nil {
		r.JourneyID = journey.String()
	}
	if err := json.Unmarshal(anchors, &r.Anchors); err != nil {
		return Route{}, err
	}
	if err := json.Unmarshal(legs, &r.Legs); err != nil {
		return Route{}, err
	}
	return r, nil
}

// ListByOwner returns a user's routes, most recently changed first.
func (s *Store) ListByOwner(ctx context.Context, ownerID uuid.UUID, limit int) ([]Summary, error) {
	return s.list(ctx, `r.owner_id = $1 AND r.journey_id IS NULL`, ownerID, limit)
}

// ListForProfile returns the routes a user's profile shows viewer (uuid.Nil
// when signed out; viewerEmail their verified address or ""): the user's own
// that are public or shared with viewer and, with hikes, those of others
// the user hiked that viewer may open.
func (s *Store) ListForProfile(ctx context.Context, ownerID, viewer uuid.UUID, viewerEmail string, hikes bool, limit int) ([]Summary, error) {
	return s.list(ctx, `r.journey_id IS NULL AND u.banned_at IS NULL
		AND (r.owner_id = $1 OR ($5 AND r.id IN (
			SELECT route_id FROM done_marks WHERE user_id = $1
			UNION SELECT planned_route_id FROM routes WHERE owner_id = $1 AND hiked_at IS NOT NULL)))
		AND (r.visibility = 'public' OR (r.owner_id = $3 AND r.owner_id <> $1)
			OR r.id IN (SELECT route_id FROM grants WHERE user_id = $3 OR (email = $4 AND $4 <> '')))`,
		ownerID, limit, viewer, viewerEmail, hikes)
}

// list returns the routes that match where ($1 ownerID, $2 limit, $3… more).
func (s *Store) list(ctx context.Context, where string, ownerID uuid.UUID, limit int, more ...any) ([]Summary, error) {
	rows, err := s.DB.Query(ctx, `SELECT `+summaryColumns+`
		FROM routes r JOIN users u ON u.id = r.owner_id
		WHERE `+where+` ORDER BY r.updated_at DESC LIMIT $2`, append([]any{ownerID, limit}, more...)...)
	if err != nil {
		return nil, fmt.Errorf("routes: list: %w", err)
	}
	defer rows.Close()
	out := []Summary{}
	for rows.Next() {
		sum, err := scanSummary(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, sum)
	}
	return out, rows.Err()
}

// SetSource records where an imported route came from (ref may be "").
// Importing the same reference twice fails with ErrDuplicate.
func (s *Store) SetSource(ctx context.Context, id uuid.UUID, source, ref string) error {
	_, err := s.DB.Exec(ctx, `UPDATE routes SET source = $2, source_ref = nullif($3, '') WHERE id = $1`, id, source, ref)
	if pgErr := (*pgconn.PgError)(nil); errors.As(err, &pgErr) && pgErr.Code == "23505" { // unique_violation
		return ErrDuplicate
	}
	return err
}

// SetHike records when a route recorded with the app was hiked and which
// planned route it followed (nil: none).
func (s *Store) SetHike(ctx context.Context, id uuid.UUID, at time.Time, seconds int, planned *uuid.UUID) error {
	_, err := s.DB.Exec(ctx, `UPDATE routes SET hiked_at = $2, hiked_s = $3, planned_route_id = $4 WHERE id = $1`,
		id, at, seconds, planned)
	return err
}

// ImportedRefs maps the references a user imported from source to the route ids.
func (s *Store) ImportedRefs(ctx context.Context, ownerID uuid.UUID, source string) (map[string]string, error) {
	rows, err := s.DB.Query(ctx, `SELECT source_ref, id FROM routes
		WHERE owner_id = $1 AND source = $2 AND source_ref IS NOT NULL`, ownerID, source)
	if err != nil {
		return nil, fmt.Errorf("routes: imported: %w", err)
	}
	defer rows.Close()
	out := map[string]string{}
	for rows.Next() {
		var ref string
		var id uuid.UUID
		if err := rows.Scan(&ref, &id); err != nil {
			return nil, err
		}
		out[ref] = id.String()
	}
	return out, rows.Err()
}

// Shared is a route someone shared with the user, with the user's role.
type Shared struct {
	Summary
	Role string `json:"role" enum:"viewer,editor"`
}

// ListSharedWith returns routes shared with the user by account or by their
// verified e-mail address ("" if unverified).
func (s *Store) ListSharedWith(ctx context.Context, userID uuid.UUID, verifiedEmail string, limit int) ([]Shared, error) {
	rows, err := s.DB.Query(ctx, `
		WITH mine AS (
			SELECT route_id, max(role)::text AS role FROM grants
			WHERE route_id IS NOT NULL AND (user_id = $1 OR (email = $2 AND $2 <> ''))
			GROUP BY route_id)
		SELECT `+summaryColumns+`, mine.role
		FROM mine JOIN routes r ON r.id = mine.route_id JOIN users u ON u.id = r.owner_id
		WHERE r.owner_id <> $1 ORDER BY r.updated_at DESC LIMIT $3`, userID, verifiedEmail, limit)
	if err != nil {
		return nil, fmt.Errorf("routes: shared: %w", err)
	}
	defer rows.Close()
	out := []Shared{}
	for rows.Next() {
		var sh Shared
		var err error
		if sh.Summary, err = scanSummary(rows, &sh.Role); err != nil {
			return nil, err
		}
		out = append(out, sh)
	}
	return out, rows.Err()
}

// Update changes a route if it is still at the given version. A nil content
// only updates the descriptive fields; new content, saved by [by], keeps the
// line it replaces as a revision.
func (s *Store) Update(ctx context.Context, id uuid.UUID, version int, m Meta, c *Content, by uuid.UUID) (Route, error) {
	var res pgconn.CommandTag
	var err error
	if c == nil {
		res, err = s.DB.Exec(ctx, `UPDATE routes SET title = $3, description = $4, visibility = $5::visibility,
			share_token = `+keepOrNewToken+`, tags = `+ownTags7+`,
			version = version + 1, updated_at = now() WHERE id = $1 AND version = $2`,
			id, version, m.Title, m.Description, m.Visibility, NewShareToken(), m.Tags)
	} else {
		a, aerr := assemble(*c)
		if aerr != nil {
			return Route{}, aerr
		}
		anchors, legs, eerr := encode(c.Anchors, a.legs)
		if eerr != nil {
			return Route{}, eerr
		}
		t := a.totals
		// The row is locked at the version first: a statement that only
		// found out in its UPDATE that another change came first would
		// already have kept and pruned revisions.
		tx, terr := s.DB.Begin(ctx)
		if terr != nil {
			return Route{}, fmt.Errorf("routes: update: %w", terr)
		}
		defer tx.Rollback(ctx) //nolint:errcheck // after Commit, a no-op
		var current int
		err = tx.QueryRow(ctx, `SELECT version FROM routes WHERE id = $1 FOR UPDATE`, id).Scan(&current)
		switch {
		case errors.Is(err, pgx.ErrNoRows):
			return Route{}, ErrNotFound
		case err != nil:
			return Route{}, fmt.Errorf("routes: update: %w", err)
		case current != version:
			return Route{}, ErrVersion
		}
		// The line replaced is kept, the oldest beyond MaxRevisions go.
		res, err = tx.Exec(ctx, `WITH kept AS (
				INSERT INTO route_revisions (route_id, version, profile, anchors, legs, distance_m, ascent_m, duration_s,
					saved_at, saved_by)
				SELECT id, version, profile, anchors, legs, distance_m, ascent_m, duration_s, content_at, coalesce(content_by, owner_id)
				FROM routes WHERE id = $1 AND version = $2
				ON CONFLICT DO NOTHING
			), pruned AS (
				DELETE FROM route_revisions WHERE route_id = $1 AND version NOT IN (
					SELECT version FROM route_revisions WHERE route_id = $1 ORDER BY version DESC LIMIT $22)
					AND EXISTS (SELECT 1 FROM routes WHERE id = $1 AND version = $2)
			)
			UPDATE routes SET title = $3, description = $4, visibility = $5::visibility, profile = $6,
			anchors = $7, legs = $8, geom = ST_GeomFromText($9, 4326),
			distance_m = $10, ascent_m = $11, descent_m = $12, duration_s = $13, duration_reverse_s = $14,
			ele_min_m = $15, ele_max_m = $16, sac_grade = $17, sac_max = $18,
			share_token = `+keepOrNewToken19+`, tags = `+ownTags20+`,
			version = version + 1, updated_at = now(), content_at = now(), content_by = $21
			WHERE id = $1 AND version = $2`,
			id, version, m.Title, m.Description, m.Visibility, c.Profile, anchors, legs, a.wkt,
			round(t.DistanceM), round(t.AscentM), round(t.DescentM), t.DurationS, t.DurationReverseS,
			round(t.EleMinM), round(t.EleMaxM), t.SACGrade, t.SACMax, NewShareToken(), m.Tags, by, MaxRevisions-1)
		if err == nil {
			err = tx.Commit(ctx)
		}
	}
	if err != nil {
		return Route{}, fmt.Errorf("routes: update: %w", err)
	}
	if res.RowsAffected() == 0 {
		if _, gerr := s.Get(ctx, id); errors.Is(gerr, ErrNotFound) {
			return Route{}, ErrNotFound
		}
		return Route{}, ErrVersion
	}
	return s.Get(ctx, id)
}

// A route keeps its share token (and so its link) across visibility changes;
// one is created the first time it becomes unlisted. $5 is the visibility.
const (
	keepOrNewToken   = `CASE WHEN $5::visibility = 'unlisted' THEN COALESCE(share_token, $6) ELSE share_token END`
	keepOrNewToken19 = `CASE WHEN $5::visibility = 'unlisted' THEN COALESCE(share_token, $19) ELSE share_token END`
	// Stage routes have their journey's tags, not their own.
	ownTags7  = `CASE WHEN journey_id IS NULL THEN coalesce($7::text[], '{}') ELSE tags END`
	ownTags20 = `CASE WHEN journey_id IS NULL THEN coalesce($20::text[], '{}') ELSE tags END`
)

// RotateShareToken replaces the share token, which breaks existing links.
func (s *Store) RotateShareToken(ctx context.Context, id uuid.UUID) (string, error) {
	token := NewShareToken()
	res, err := s.DB.Exec(ctx, `UPDATE routes SET share_token = $2 WHERE id = $1`, id, token)
	if err != nil {
		return "", fmt.Errorf("routes: rotate token: %w", err)
	}
	if res.RowsAffected() == 0 {
		return "", ErrNotFound
	}
	return token, nil
}

// NewShareToken returns a random, URL-safe 22-character token.
func NewShareToken() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}

// Delete removes a route.
func (s *Store) Delete(ctx context.Context, id uuid.UUID) error {
	res, err := s.DB.Exec(ctx, `DELETE FROM routes WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("routes: delete: %w", err)
	}
	if res.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func encode(anchors []Anchor, legs any) (a, l []byte, err error) {
	if a, err = json.Marshal(anchors); err != nil {
		return nil, nil, err
	}
	l, err = json.Marshal(legs)
	return a, l, err
}

func round(x float64) int { return int(x + 0.5) }
