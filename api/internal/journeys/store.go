package journeys

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tellbow/odysgeh/api/internal/access"
	"github.com/tellbow/odysgeh/api/internal/places"
	"github.com/tellbow/odysgeh/api/internal/routes"
	"github.com/tellbow/odysgeh/swiss/geo"
)

// Store errors.
var (
	ErrNotFound      = errors.New("journey not found")
	ErrStageNotFound = errors.New("stage not found")
	ErrVersion       = errors.New("journey was changed by someone else")
	ErrHasRoute      = errors.New("stage already has a route")
	ErrBadOrder      = errors.New("order must list every stage exactly once")
	ErrNotYours      = errors.New("route belongs to someone else")
)

// MaxStages bounds a journey (a year of daily stages is plenty).
const MaxStages = 400

// Store reads and writes journeys.
type Store struct {
	DB     *pgxpool.Pool
	Routes *routes.Store
}

// Create stores a new journey.
func (s *Store) Create(ctx context.Context, ownerID uuid.UUID, m Meta) (Journey, error) {
	var id uuid.UUID
	err := s.DB.QueryRow(ctx, `INSERT INTO journeys (owner_id, title, description, visibility, share_token)
		VALUES ($1, $2, $3, $4::visibility, CASE WHEN $4::visibility = 'unlisted' THEN $5 END) RETURNING id`,
		ownerID, m.Title, m.Description, m.Visibility, routes.NewShareToken()).Scan(&id)
	if err != nil {
		return Journey{}, fmt.Errorf("journeys: create: %w", err)
	}
	return s.Get(ctx, id)
}

// listSQL selects journey summaries; callers add joins and conditions.
const listSQL = `
	SELECT j.id, u.username, j.title, j.description, j.visibility, j.version, j.created_at, j.updated_at,
		count(st.id), count(st.id) FILTER (WHERE st.status = 'done'),
		coalesce(sum(r.distance_m), 0), coalesce(sum(r.ascent_m), 0), coalesce(sum(r.duration_s), 0)%s
	FROM journeys j
	JOIN users u ON u.id = j.owner_id
	LEFT JOIN stages st ON st.journey_id = j.id
	LEFT JOIN routes r ON r.id = st.route_id
	%s
	GROUP BY j.id, u.username%s
	ORDER BY j.updated_at DESC`

func scanSummary(row pgx.Row, extra ...any) (Summary, error) {
	var sm Summary
	var id uuid.UUID
	err := row.Scan(append([]any{&id, &sm.OwnerUsername, &sm.Title, &sm.Description, &sm.Visibility, &sm.Version,
		&sm.CreatedAt, &sm.UpdatedAt, &sm.Stages, &sm.StagesDone, &sm.DistanceM, &sm.AscentM, &sm.DurationS}, extra...)...)
	sm.ID = id.String()
	return sm, err
}

// ListByOwner returns a user's journeys with their stage counts and totals.
func (s *Store) ListByOwner(ctx context.Context, ownerID uuid.UUID) ([]Summary, error) {
	return s.listByOwner(ctx, "WHERE j.owner_id = $1", ownerID)
}

// ListPublicByOwner returns a user's public journeys.
func (s *Store) ListPublicByOwner(ctx context.Context, ownerID uuid.UUID) ([]Summary, error) {
	return s.listByOwner(ctx, "WHERE j.owner_id = $1 AND j.visibility = 'public'", ownerID)
}

func (s *Store) listByOwner(ctx context.Context, where string, ownerID uuid.UUID) ([]Summary, error) {
	rows, err := s.DB.Query(ctx, fmt.Sprintf(listSQL, "", where, ""), ownerID)
	if err != nil {
		return nil, fmt.Errorf("journeys: list: %w", err)
	}
	defer rows.Close()
	out := []Summary{}
	for rows.Next() {
		sm, err := scanSummary(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, sm)
	}
	return out, rows.Err()
}

// Shared is a journey someone shared with the user, with the user's role.
type Shared struct {
	Summary
	Role string `json:"role" enum:"viewer,editor"`
}

// ListSharedWith returns journeys shared with the user by account or by
// their verified e-mail address ("" if unverified).
func (s *Store) ListSharedWith(ctx context.Context, userID uuid.UUID, verifiedEmail string) ([]Shared, error) {
	rows, err := s.DB.Query(ctx, fmt.Sprintf(listSQL, ", mine.role",
		`JOIN (SELECT journey_id, max(role)::text AS role FROM grants
			WHERE journey_id IS NOT NULL AND (user_id = $1 OR (email = $2 AND $2 <> ''))
			GROUP BY journey_id) mine ON mine.journey_id = j.id
		WHERE j.owner_id <> $1`, ", mine.role"), userID, verifiedEmail)
	if err != nil {
		return nil, fmt.Errorf("journeys: shared: %w", err)
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

// Get loads a journey with its stages and derived numbers.
func (s *Store) Get(ctx context.Context, id uuid.UUID) (Journey, error) {
	var j Journey
	var jid, owner uuid.UUID
	var token *string
	err := s.DB.QueryRow(ctx, `
		SELECT j.id, u.username, j.title, j.description, j.visibility, j.version, j.created_at, j.updated_at,
			j.owner_id, j.share_token
		FROM journeys j JOIN users u ON u.id = j.owner_id WHERE j.id = $1`, id).
		Scan(&jid, &j.OwnerUsername, &j.Title, &j.Description, &j.Visibility, &j.Version, &j.CreatedAt, &j.UpdatedAt,
			&owner, &token)
	if errors.Is(err, pgx.ErrNoRows) {
		return Journey{}, ErrNotFound
	}
	if err != nil {
		return Journey{}, fmt.Errorf("journeys: get: %w", err)
	}
	j.ID, j.OwnerID = jid.String(), owner.String()
	if token != nil {
		j.ShareToken = *token
	}

	rows, err := s.DB.Query(ctx, `
		SELECT st.id, st.position, st.title, to_char(st.planned_date, 'YYYY-MM-DD'), st.status,
			to_char(st.done_on, 'YYYY-MM-DD'), st.transfer_before, st.notes, st.accommodation, st.accommodation_booked,
			r.id, r.distance_m, r.ascent_m, r.descent_m, r.duration_s, r.duration_reverse_s,
			r.ele_min_m, r.ele_max_m, r.sac_grade, r.sac_max,
			ST_AsGeoJSON(ST_Simplify(ST_Force2D(r.geom), 0.00005, true), 6), r.legs, -- true: a tiny loop stays a line
			sp.id, sp.kind, sp.name, sp.detail, sp.ref, sp.lon, sp.lat, sp.dist, sp.suggested,
			ep.id, ep.kind, ep.name, ep.detail, ep.ref, ep.lon, ep.lat, ep.dist, ep.suggested
		FROM stages st LEFT JOIN routes r ON r.id = st.route_id
		LEFT JOIN LATERAL (`+stagePlace("st.start_place_id", "ST_StartPoint(r.geom)")+`) sp ON true
		LEFT JOIN LATERAL (`+stagePlace("st.end_place_id", "ST_EndPoint(r.geom)")+`) ep ON true
		WHERE st.journey_id = $1 ORDER BY st.position`, id)
	if err != nil {
		return Journey{}, fmt.Errorf("journeys: stages: %w", err)
	}
	defer rows.Close()
	j.StageList = []Stage{}
	for rows.Next() {
		var st Stage
		var sid uuid.UUID
		var rid *uuid.UUID
		var t routes.Totals
		var dist, asc, desc, dur, durRev, eleMin, eleMax, sacGrade, sacMax *int
		var line, legs []byte
		var sp, ep placeRow
		if err := rows.Scan(&sid, &st.Position, &st.Title, &st.PlannedDate, &st.Status, &st.DoneOn, &st.TransferBefore,
			&st.Notes, &st.Accommodation, &st.AccommodationBooked,
			&rid, &dist, &asc, &desc, &dur, &durRev, &eleMin, &eleMax, &sacGrade, &sacMax, &line, &legs,
			&sp.id, &sp.kind, &sp.name, &sp.detail, &sp.ref, &sp.lon, &sp.lat, &sp.dist, &sp.suggested,
			&ep.id, &ep.kind, &ep.name, &ep.detail, &ep.ref, &ep.lon, &ep.lat, &ep.dist, &ep.suggested); err != nil {
			return Journey{}, err
		}
		st.ID = sid.String()
		st.StartPlace, st.EndPlace = sp.place(), ep.place()
		if rid != nil {
			t = routes.Totals{
				DistanceM: float64(*dist), AscentM: float64(*asc), DescentM: float64(*desc),
				DurationS: *dur, DurationReverseS: *durRev, EleMinM: float64(*eleMin), EleMaxM: float64(*eleMax),
				SACGrade: *sacGrade, SACMax: *sacMax,
			}
			sr, full, err := decodeRoute(rid.String(), t, line, legs)
			if err != nil {
				return Journey{}, err
			}
			st.Route, st.line = sr, full
		}
		j.StageList = append(j.StageList, st)
	}
	if err := rows.Err(); err != nil {
		return Journey{}, err
	}
	j.Stages = len(j.StageList)
	j.derive()
	return j, nil
}

// stagePlace selects the explicit place of a stage end, or else the nearest
// stop or hut to the route's end point (filtered by distance in placeRow).
func stagePlace(explicit, point string) string {
	return fmt.Sprintf(`
		SELECT p.id, p.kind, p.name, p.detail, CASE WHEN p.source = 'didok' THEN p.source_id ELSE '' END AS ref,
			ST_X(p.geom) AS lon, ST_Y(p.geom) AS lat,
			ST_Distance(p.geom::geography, %[2]s::geography) AS dist, false AS suggested
		FROM places p WHERE p.id = %[1]s
		UNION ALL
		(SELECT p.id, p.kind, p.name, p.detail, CASE WHEN p.source = 'didok' THEN p.source_id ELSE '' END,
			ST_X(p.geom), ST_Y(p.geom), ST_Distance(p.geom::geography, %[2]s::geography), true
		FROM places p WHERE %[1]s IS NULL AND r.geom IS NOT NULL AND p.kind IN ('pt_stop', 'hut')
		ORDER BY p.geom <-> %[2]s LIMIT 1)`, explicit, point)
}

// placeRow is a stage place as scanned; every column is NULL without one.
type placeRow struct {
	id                      *uuid.UUID
	kind, name, detail, ref *string
	lon, lat, dist          *float64
	suggested               *bool
}

func (r placeRow) place() *places.Place {
	if r.id == nil {
		return nil
	}
	p := &places.Place{ID: r.id.String(), Kind: *r.kind, Name: *r.name, Detail: *r.detail, Ref: *r.ref,
		At: [2]float64{*r.lon, *r.lat}, Suggested: *r.suggested}
	if r.dist != nil {
		p.DistanceM = math.Round(*r.dist)
	}
	if p.Suggested && p.DistanceM > suggestRadius {
		return nil
	}
	return p
}

func decodeRoute(id string, t routes.Totals, line, legs []byte) (*StageRoute, [][3]float64, error) {
	var g struct {
		Coordinates [][2]float64 `json:"coordinates"`
	}
	if err := json.Unmarshal(line, &g); err != nil {
		return nil, nil, fmt.Errorf("journeys: line: %w", err)
	}
	var ls []struct {
		Coordinates [][3]float64 `json:"coordinates"`
	}
	if err := json.Unmarshal(legs, &ls); err != nil {
		return nil, nil, fmt.Errorf("journeys: legs: %w", err)
	}
	var full [][3]float64
	for _, l := range ls {
		c := l.Coordinates
		if n := len(full); n > 0 && len(c) > 0 &&
			geo.Distance(geo.Point{Lon: full[n-1][0], Lat: full[n-1][1]}, geo.Point{Lon: c[0][0], Lat: c[0][1]}) < 0.5 {
			c = c[1:] // shared joint between legs
		}
		full = append(full, c...)
	}
	sr := &StageRoute{ID: id, Totals: t, Line: g.Coordinates}
	if len(full) > 0 {
		first, last := full[0], full[len(full)-1]
		sr.Start, sr.End = [2]float64{first[0], first[1]}, [2]float64{last[0], last[1]}
	}
	return sr, full, nil
}

// Access returns what decides who may see a journey (and its stage routes);
// the caller adds their grant.
func (s *Store) Access(ctx context.Context, id uuid.UUID) (access.Resource, error) {
	var res access.Resource
	var owner uuid.UUID
	var token *string
	err := s.DB.QueryRow(ctx, `SELECT owner_id, visibility, share_token FROM journeys WHERE id = $1`, id).
		Scan(&owner, &res.Visibility, &token)
	if errors.Is(err, pgx.ErrNoRows) {
		return res, ErrNotFound
	}
	res.OwnerID = owner.String()
	if token != nil {
		res.ShareToken = *token
	}
	return res, err
}

// UpdateMeta changes the descriptive fields if still at version. A share
// token is created the first time the journey becomes unlisted.
func (s *Store) UpdateMeta(ctx context.Context, id uuid.UUID, version int, m Meta) (Journey, error) {
	res, err := s.DB.Exec(ctx, `UPDATE journeys SET title = $3, description = $4, visibility = $5::visibility,
		share_token = CASE WHEN $5::visibility = 'unlisted' THEN coalesce(share_token, $6) ELSE share_token END,
		version = version + 1, updated_at = now() WHERE id = $1 AND version = $2`,
		id, version, m.Title, m.Description, m.Visibility, routes.NewShareToken())
	if err != nil {
		return Journey{}, fmt.Errorf("journeys: update: %w", err)
	}
	if res.RowsAffected() == 0 {
		if _, err := s.Get(ctx, id); errors.Is(err, ErrNotFound) {
			return Journey{}, ErrNotFound
		}
		return Journey{}, ErrVersion
	}
	return s.Get(ctx, id)
}

// Delete removes a journey, its stages and their routes.
func (s *Store) Delete(ctx context.Context, id uuid.UUID) error {
	res, err := s.DB.Exec(ctx, `DELETE FROM journeys WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("journeys: delete: %w", err)
	}
	if res.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// RotateShareToken replaces the share link.
func (s *Store) RotateShareToken(ctx context.Context, id uuid.UUID) (string, error) {
	token := routes.NewShareToken()
	if _, err := s.DB.Exec(ctx, `UPDATE journeys SET share_token = $2 WHERE id = $1`, id, token); err != nil {
		return "", err
	}
	return token, nil
}

// NewStage describes a stage to add.
type NewStage struct {
	Title    string
	Position *int       // 0-based; nil appends
	CopyFrom *uuid.UUID // an existing route of the owner to copy into the stage
}

// AddStage inserts a stage, shifting later stages back.
func (s *Store) AddStage(ctx context.Context, journeyID, ownerID uuid.UUID, n NewStage) error {
	return s.tx(ctx, journeyID, func(tx pgx.Tx) error {
		var count int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM stages WHERE journey_id = $1`, journeyID).Scan(&count); err != nil {
			return err
		}
		if count >= MaxStages {
			return fmt.Errorf("%w: at most %d stages", routes.ErrInvalid, MaxStages)
		}
		pos := count
		if n.Position != nil && *n.Position >= 0 && *n.Position < count {
			pos = *n.Position
			if _, err := tx.Exec(ctx, `UPDATE stages SET position = position + 1 WHERE journey_id = $1 AND position >= $2`,
				journeyID, pos); err != nil {
				return err
			}
		}
		var routeID *uuid.UUID
		if n.CopyFrom != nil {
			id, err := copyRoute(ctx, tx, *n.CopyFrom, ownerID, journeyID)
			if err != nil {
				return err
			}
			routeID = &id
		}
		_, err := tx.Exec(ctx, `INSERT INTO stages (journey_id, position, title, route_id) VALUES ($1, $2, $3, $4)`,
			journeyID, pos, n.Title, routeID)
		return err
	})
}

// copyRoute copies one of the caller's routes into the journey; the journey
// owner owns the copy.
func copyRoute(ctx context.Context, tx pgx.Tx, from, ownerID, journeyID uuid.UUID) (uuid.UUID, error) {
	var id uuid.UUID
	err := tx.QueryRow(ctx, `
		INSERT INTO routes (owner_id, journey_id, title, description, visibility, profile, anchors, legs, geom,
			distance_m, ascent_m, descent_m, duration_s, duration_reverse_s, ele_min_m, ele_max_m, sac_grade, sac_max)
		SELECT (SELECT owner_id FROM journeys WHERE id = $3), $3, title, description, 'private', profile, anchors, legs, geom,
			distance_m, ascent_m, descent_m, duration_s, duration_reverse_s, ele_min_m, ele_max_m, sac_grade, sac_max
		FROM routes WHERE id = $1 AND owner_id = $2
		RETURNING id`, from, ownerID, journeyID).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, ErrNotYours
	}
	return id, err
}

// StagePatch holds the stage fields to change; nil leaves a field alone.
type StagePatch struct {
	Title          *string
	PlannedDate    *string // "" clears
	Status         *string
	DoneOn         *string // "" clears
	TransferBefore *string // "" clears
	Notes          *string
	StartPlaceID   *string // "" clears (back to the suggestion)
	EndPlaceID     *string // "" clears
	Accommodation  *string
	Booked         *bool
}

// UpdateStage changes a stage's fields.
func (s *Store) UpdateStage(ctx context.Context, journeyID, stageID uuid.UUID, p StagePatch) error {
	return s.tx(ctx, journeyID, func(tx pgx.Tx) error {
		res, err := tx.Exec(ctx, `UPDATE stages SET
			title = coalesce($3, title),
			planned_date = CASE WHEN $4::text IS NULL THEN planned_date ELSE nullif($4, '')::date END,
			status = coalesce($5::stage_status, status),
			done_on = CASE WHEN $6::text IS NULL THEN done_on ELSE nullif($6, '')::date END,
			transfer_before = CASE WHEN $7::text IS NULL THEN transfer_before ELSE nullif($7, '') END,
			notes = coalesce($8, notes),
			start_place_id = CASE WHEN $9::text IS NULL THEN start_place_id ELSE nullif($9, '')::uuid END,
			end_place_id = CASE WHEN $10::text IS NULL THEN end_place_id ELSE nullif($10, '')::uuid END,
			accommodation = coalesce($11, accommodation),
			accommodation_booked = coalesce($12, accommodation_booked),
			updated_at = now()
			WHERE id = $2 AND journey_id = $1`,
			journeyID, stageID, p.Title, p.PlannedDate, p.Status, p.DoneOn, p.TransferBefore, p.Notes,
			p.StartPlaceID, p.EndPlaceID, p.Accommodation, p.Booked)
		if pgErr := (*pgconn.PgError)(nil); errors.As(err, &pgErr) && pgErr.Code == "23503" { // foreign_key_violation
			return fmt.Errorf("%w: unknown place", routes.ErrInvalid)
		}
		if err != nil {
			return err
		}
		if res.RowsAffected() == 0 {
			return ErrStageNotFound
		}
		return nil
	})
}

// DeleteStage removes a stage and its route, closing the gap in positions.
func (s *Store) DeleteStage(ctx context.Context, journeyID, stageID uuid.UUID) error {
	return s.tx(ctx, journeyID, func(tx pgx.Tx) error {
		var pos int
		var routeID *uuid.UUID
		err := tx.QueryRow(ctx, `DELETE FROM stages WHERE id = $2 AND journey_id = $1 RETURNING position, route_id`,
			journeyID, stageID).Scan(&pos, &routeID)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrStageNotFound
		}
		if err != nil {
			return err
		}
		if routeID != nil {
			if _, err := tx.Exec(ctx, `DELETE FROM routes WHERE id = $1`, *routeID); err != nil {
				return err
			}
		}
		_, err = tx.Exec(ctx, `UPDATE stages SET position = position - 1 WHERE journey_id = $1 AND position > $2`,
			journeyID, pos)
		return err
	})
}

// Reorder sets the stage order; ids must list every stage exactly once.
func (s *Store) Reorder(ctx context.Context, journeyID uuid.UUID, ids []uuid.UUID) error {
	return s.tx(ctx, journeyID, func(tx pgx.Tx) error {
		var n int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM stages WHERE journey_id = $1`, journeyID).Scan(&n); err != nil {
			return err
		}
		seen := map[uuid.UUID]bool{}
		for _, id := range ids {
			seen[id] = true
		}
		if len(ids) != n || len(seen) != n {
			return ErrBadOrder
		}
		for pos, id := range ids {
			res, err := tx.Exec(ctx, `UPDATE stages SET position = $3 WHERE id = $2 AND journey_id = $1`, journeyID, id, pos)
			if err != nil {
				return err
			}
			if res.RowsAffected() == 0 {
				return ErrBadOrder
			}
		}
		return nil
	})
}

// SetStageRoute creates the route of a stage that has none yet.
func (s *Store) SetStageRoute(ctx context.Context, journeyID, stageID, ownerID uuid.UUID, title string, c routes.Content) (uuid.UUID, error) {
	var routeID uuid.UUID
	err := s.tx(ctx, journeyID, func(tx pgx.Tx) error {
		var existing *uuid.UUID
		err := tx.QueryRow(ctx, `SELECT route_id FROM stages WHERE id = $2 AND journey_id = $1 FOR UPDATE`,
			journeyID, stageID).Scan(&existing)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrStageNotFound
		}
		if err != nil {
			return err
		}
		if existing != nil {
			return ErrHasRoute
		}
		if routeID, err = s.Routes.CreateInJourney(ctx, tx, ownerID, journeyID, title, c); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `UPDATE stages SET route_id = $2, updated_at = now() WHERE id = $1`, stageID, routeID)
		return err
	})
	return routeID, err
}

// tx runs fn in a transaction and marks the journey as changed.
func (s *Store) tx(ctx context.Context, journeyID uuid.UUID, fn func(pgx.Tx) error) error {
	return pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		// Marking the journey changed first locks it: changes to its stages
		// (counted, then shifted) go one after the other.
		if _, err := tx.Exec(ctx, `UPDATE journeys SET updated_at = now() WHERE id = $1`, journeyID); err != nil {
			return err
		}
		return fn(tx)
	})
}

// StageLines returns the lines of a journey's stage routes (lon, lat).
func (s *Store) StageLines(ctx context.Context, id uuid.UUID) ([][]geo.Point, error) {
	rows, err := s.DB.Query(ctx, `SELECT ST_AsGeoJSON(ST_Force2D(r.geom))
		FROM stages st JOIN routes r ON r.id = st.route_id
		WHERE st.journey_id = $1 ORDER BY st.position`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var lines [][]geo.Point
	for rows.Next() {
		var g string
		if err := rows.Scan(&g); err != nil {
			return nil, err
		}
		var line struct {
			Coordinates [][2]float64 `json:"coordinates"`
		}
		if err := json.Unmarshal([]byte(g), &line); err != nil {
			return nil, err
		}
		pts := make([]geo.Point, len(line.Coordinates))
		for i, c := range line.Coordinates {
			pts[i] = geo.Point{Lon: c[0], Lat: c[1]}
		}
		lines = append(lines, pts)
	}
	return lines, rows.Err()
}
