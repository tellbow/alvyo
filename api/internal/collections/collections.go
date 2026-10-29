// Package collections stores ordered lists of routes and journeys. A
// collection shares the items their owners added with whoever sees the
// collection; items others added stay visible only to those who may open
// them anyway (their own, public ones, or shared with them).
package collections

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tellbow/alvyo/api/internal/access"
	"github.com/tellbow/alvyo/api/internal/routes"
)

// MaxItems bounds a collection.
const MaxItems = 500

// Store errors.
var (
	ErrNotFound     = errors.New("collection not found")
	ErrItemNotFound = errors.New("item not found")
	ErrVersion      = errors.New("collection was changed by someone else")
	ErrDuplicate    = errors.New("already in the collection")
	ErrFull         = errors.New("the collection is full")
)

// Meta is the descriptive part of a collection.
type Meta struct {
	Title       string   `json:"title"`
	Description string   `json:"description"`
	Visibility  string   `json:"visibility" enum:"private,unlisted,public"`
	Tags        []string `json:"tags"`
}

// Summary is a collection in lists.
type Summary struct {
	ID            string `json:"id" format:"uuid"`
	OwnerUsername string `json:"owner_username"`
	Meta
	Items     int       `json:"items" doc:"Number of items, including ones the viewer may not see"`
	Version   int       `json:"version"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// Shared is a collection someone shared with the user, with the user's role.
type Shared struct {
	Summary
	Role string `json:"role" enum:"viewer,editor"`
}

// Item is a route or journey in a collection, as the viewer may see it.
type Item struct {
	ID            string `json:"id" format:"uuid"`
	Position      int    `json:"position"`
	Note          string `json:"note"`
	Kind          string `json:"kind" enum:"route,journey"`
	TargetID      string `json:"target_id" format:"uuid" doc:"The route or journey"`
	Title         string `json:"title"`
	OwnerUsername string `json:"owner_username"`
	Visibility    string `json:"visibility" enum:"private,unlisted,public"`
	// Totals of the route, or summed over the journey's stages.
	DistanceM float64 `json:"distance_m"`
	AscentM   float64 `json:"ascent_m"`
	DurationS int     `json:"duration_s"`
	SACGrade  int     `json:"sac_grade"`
	SACMax    int     `json:"sac_max"`
	Stages    int     `json:"stages" doc:"Journeys only"`
	// Lines are simplified (lon, lat) lines for the overview map.
	Lines [][][2]float64 `json:"lines"`
	// DoneOn is when the viewer hiked it, as on the route and journey pages.
	DoneOn     *string `json:"done_on,omitempty" format:"date"`
	DoneMarked bool    `json:"done_marked" doc:"By the viewer's own mark, which can be taken back"`
}

// Collection is a collection with the items the viewer may see.
type Collection struct {
	Summary
	OwnerID    string `json:"-"`
	ShareToken string `json:"-"`
	ItemList   []Item `json:"item_list"`
	Hidden     int    `json:"hidden" doc:"Number of items the viewer may not see"`
}

// Viewer is who reads a collection; the zero value is anonymous.
type Viewer struct {
	UserID        uuid.UUID
	VerifiedEmail string
}

// Store reads and writes collections.
type Store struct {
	DB *pgxpool.Pool
}

const summarySQL = `
	SELECT c.id, u.username, c.title, c.description, c.visibility, c.tags, c.version, c.created_at, c.updated_at,
		(SELECT count(*) FROM collection_items ci WHERE ci.collection_id = c.id)%s
	FROM collections c JOIN users u ON u.id = c.owner_id
	%s
	ORDER BY c.updated_at DESC`

func scanSummary(row pgx.Row, extra ...any) (Summary, error) {
	var sm Summary
	var id uuid.UUID
	err := row.Scan(append([]any{&id, &sm.OwnerUsername, &sm.Title, &sm.Description, &sm.Visibility, &sm.Tags, &sm.Version,
		&sm.CreatedAt, &sm.UpdatedAt, &sm.Items}, extra...)...)
	sm.ID = id.String()
	return sm, err
}

// Create stores a new collection.
func (s *Store) Create(ctx context.Context, ownerID uuid.UUID, m Meta) (uuid.UUID, error) {
	var id uuid.UUID
	err := s.DB.QueryRow(ctx, `INSERT INTO collections (owner_id, title, description, visibility, share_token, tags)
		VALUES ($1, $2, $3, $4::visibility, CASE WHEN $4::visibility = 'unlisted' THEN $5 END, coalesce($6::text[], '{}'))
		RETURNING id`,
		ownerID, m.Title, m.Description, m.Visibility, routes.NewShareToken(), m.Tags).Scan(&id)
	if err != nil {
		return uuid.Nil, fmt.Errorf("collections: create: %w", err)
	}
	return id, nil
}

// ListByOwner returns a user's collections.
func (s *Store) ListByOwner(ctx context.Context, ownerID uuid.UUID) ([]Summary, error) {
	rows, err := s.DB.Query(ctx, fmt.Sprintf(summarySQL, "", "WHERE c.owner_id = $1"), ownerID)
	if err != nil {
		return nil, fmt.Errorf("collections: list: %w", err)
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (Summary, error) { return scanSummary(r) })
}

// ListSharedWith returns collections shared with the user.
func (s *Store) ListSharedWith(ctx context.Context, v Viewer) ([]Shared, error) {
	rows, err := s.DB.Query(ctx, fmt.Sprintf(summarySQL, ", mine.role", `
		JOIN (SELECT collection_id, max(role)::text AS role FROM grants
			WHERE collection_id IS NOT NULL AND (user_id = $1 OR (email = $2 AND $2 <> ''))
			GROUP BY collection_id) mine ON mine.collection_id = c.id
		WHERE c.owner_id <> $1`), v.UserID, v.VerifiedEmail)
	if err != nil {
		return nil, fmt.Errorf("collections: shared: %w", err)
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (Shared, error) {
		var sh Shared
		var err error
		sh.Summary, err = scanSummary(r, &sh.Role)
		return sh, err
	})
}

// Access returns what decides who may see a collection; the caller adds
// their grant.
func (s *Store) Access(ctx context.Context, id uuid.UUID) (access.Resource, error) {
	var res access.Resource
	var owner uuid.UUID
	var token *string
	err := s.DB.QueryRow(ctx, `SELECT owner_id, visibility, share_token FROM collections WHERE id = $1`, id).
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

// visibleSQL is true for an item the viewer ($2 user, $3 verified e-mail)
// of the collection may open: one its owner added, or one they may open
// anyway without a share token.
const visibleSQL = `(
	ci.added_by = coalesce(r.owner_id, j.owner_id)
	OR (ci.route_id IS NOT NULL AND (r.owner_id = $2 OR r.visibility = 'public' OR EXISTS (
		SELECT 1 FROM grants g WHERE g.route_id = r.id AND (g.user_id = $2 OR (g.email = $3 AND $3 <> '')))))
	OR (ci.journey_id IS NOT NULL AND (j.owner_id = $2 OR j.visibility = 'public' OR EXISTS (
		SELECT 1 FROM grants g WHERE g.journey_id = j.id AND (g.user_id = $2 OR (g.email = $3 AND $3 <> ''))))))`

// Get loads a collection with the items the viewer may see.
func (s *Store) Get(ctx context.Context, id uuid.UUID, v Viewer) (Collection, error) {
	var c Collection
	var owner uuid.UUID
	var token *string
	sm, err := scanSummary(s.DB.QueryRow(ctx, fmt.Sprintf(summarySQL, ", c.owner_id, c.share_token", "WHERE c.id = $1"), id),
		&owner, &token)
	if errors.Is(err, pgx.ErrNoRows) {
		return c, ErrNotFound
	}
	if err != nil {
		return c, fmt.Errorf("collections: get: %w", err)
	}
	c.Summary, c.OwnerID = sm, owner.String()
	if token != nil {
		c.ShareToken = *token
	}

	rows, err := s.DB.Query(ctx, `
		SELECT ci.id, ci.position, ci.note,
			CASE WHEN ci.route_id IS NOT NULL THEN 'route' ELSE 'journey' END,
			coalesce(ci.route_id, ci.journey_id), coalesce(r.title, j.title), u.username,
			coalesce(r.visibility, j.visibility),
			coalesce(r.distance_m, js.distance_m, 0), coalesce(r.ascent_m, js.ascent_m, 0),
			coalesce(r.duration_s, js.duration_s, 0), coalesce(r.sac_grade, js.sac_grade, 0),
			coalesce(r.sac_max, js.sac_max, 0), coalesce(js.stages, 0),
			-- others' recorded hikes without their start and end
			coalesce(ST_AsGeoJSON(ST_Simplify(ST_Force2D(
				CASE WHEN r.hiked_at IS NULL OR r.owner_id = $2 THEN r.geom ELSE shown_line(r.geom) END), 0.0002), 5), js.lines),
			to_char(CASE WHEN ci.route_id IS NOT NULL THEN route_done_on(r, $2) ELSE journey_done_on(j.id, $2) END, 'YYYY-MM-DD'),
			EXISTS (SELECT 1 FROM done_marks dm WHERE dm.user_id = $2
				AND (dm.route_id = ci.route_id OR dm.journey_id = ci.journey_id))
		FROM collection_items ci
		LEFT JOIN routes r ON r.id = ci.route_id
		LEFT JOIN journeys j ON j.id = ci.journey_id
		JOIN users u ON u.id = coalesce(r.owner_id, j.owner_id)
		LEFT JOIN LATERAL (
			SELECT count(st.id) AS stages, sum(sr.distance_m) AS distance_m, sum(sr.ascent_m) AS ascent_m,
				sum(sr.duration_s) AS duration_s, max(sr.sac_grade) AS sac_grade, max(sr.sac_max) AS sac_max,
				ST_AsGeoJSON(ST_Simplify(ST_Force2D(ST_Collect(sr.geom)), 0.0002), 5) AS lines
			FROM stages st LEFT JOIN routes sr ON sr.id = st.route_id
			WHERE st.journey_id = j.id) js ON ci.journey_id IS NOT NULL
		WHERE ci.collection_id = $1 AND `+visibleSQL+`
		ORDER BY ci.position`, id, v.UserID, v.VerifiedEmail)
	if err != nil {
		return c, fmt.Errorf("collections: items: %w", err)
	}
	defer rows.Close()
	c.ItemList = []Item{}
	for rows.Next() {
		var it Item
		var itemID, targetID uuid.UUID
		var geom *string
		if err := rows.Scan(&itemID, &it.Position, &it.Note, &it.Kind, &targetID, &it.Title, &it.OwnerUsername,
			&it.Visibility, &it.DistanceM, &it.AscentM, &it.DurationS, &it.SACGrade, &it.SACMax, &it.Stages, &geom,
			&it.DoneOn, &it.DoneMarked); err != nil {
			return c, err
		}
		it.ID, it.TargetID = itemID.String(), targetID.String()
		if it.Lines, err = decodeLines(geom); err != nil {
			return c, err
		}
		c.ItemList = append(c.ItemList, it)
	}
	c.Hidden = c.Items - len(c.ItemList)
	return c, rows.Err()
}

// sharedSQL joins the items holding a route or journey added by its owner
// (ci, the item as t, its collection as c); %[1]s is the table, %[2]s the
// kind.
const sharedSQL = `FROM collection_items ci
	JOIN %[1]s t ON t.id = ci.%[2]s_id AND ci.added_by = t.owner_id
	JOIN collections c ON c.id = ci.collection_id`

// RoleOf returns the best role the viewer holds on the route or journey
// (kind "route" or "journey") through collections they own or were invited
// to that share it: their role there, an owner's as editor.
func (s *Store) RoleOf(ctx context.Context, kind string, target uuid.UUID, v Viewer) (access.Role, error) {
	var role *string
	err := s.DB.QueryRow(ctx, `SELECT max(CASE WHEN c.owner_id = $1 THEN 'editor' ELSE g.role END)::text
		`+fmt.Sprintf(sharedSQL, kind+"s", kind)+`
		LEFT JOIN grants g ON g.collection_id = c.id AND (g.user_id = $1 OR (g.email = $3 AND $3 <> ''))
		WHERE t.id = $2 AND (c.owner_id = $1 OR g.id IS NOT NULL)`, v.UserID, target, v.VerifiedEmail).Scan(&role)
	if err != nil || role == nil {
		return access.None, err
	}
	return access.ParseGrant(*role), nil
}

// Shares reports whether the collection shares the route or journey (kind
// "route" or "journey"): it holds it, added by its owner.
func (s *Store) Shares(ctx context.Context, id uuid.UUID, kind string, target uuid.UUID) (bool, error) {
	var ok bool
	err := s.DB.QueryRow(ctx, `SELECT EXISTS (SELECT 1 `+fmt.Sprintf(sharedSQL, kind+"s", kind)+`
		WHERE c.id = $1 AND t.id = $2)`, id, target).Scan(&ok)
	if err != nil {
		return false, fmt.Errorf("collections: shares: %w", err)
	}
	return ok, nil
}

// decodeLines reads a GeoJSON LineString or MultiLineString.
func decodeLines(geom *string) ([][][2]float64, error) {
	out := [][][2]float64{}
	if geom == nil {
		return out, nil
	}
	var g struct {
		Type        string          `json:"type"`
		Coordinates json.RawMessage `json:"coordinates"`
	}
	if err := json.Unmarshal([]byte(*geom), &g); err != nil {
		return nil, fmt.Errorf("collections: lines: %w", err)
	}
	switch g.Type {
	case "LineString":
		var l [][2]float64
		if err := json.Unmarshal(g.Coordinates, &l); err != nil {
			return nil, err
		}
		out = append(out, l)
	case "MultiLineString":
		if err := json.Unmarshal(g.Coordinates, &out); err != nil {
			return nil, err
		}
	}
	return out, nil
}

// UpdateMeta changes the descriptive fields if still at version.
func (s *Store) UpdateMeta(ctx context.Context, id uuid.UUID, version int, m Meta) error {
	res, err := s.DB.Exec(ctx, `UPDATE collections SET title = $3, description = $4, visibility = $5::visibility,
		share_token = CASE WHEN $5::visibility = 'unlisted' THEN coalesce(share_token, $6) ELSE share_token END,
		tags = coalesce($7::text[], '{}'), version = version + 1, updated_at = now() WHERE id = $1 AND version = $2`,
		id, version, m.Title, m.Description, m.Visibility, routes.NewShareToken(), m.Tags)
	if err != nil {
		return fmt.Errorf("collections: update: %w", err)
	}
	if res.RowsAffected() == 0 {
		return ErrVersion
	}
	return nil
}

// Delete removes a collection (not its items' routes and journeys).
func (s *Store) Delete(ctx context.Context, id uuid.UUID) error {
	res, err := s.DB.Exec(ctx, `DELETE FROM collections WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if res.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// RotateShareToken replaces the share link.
func (s *Store) RotateShareToken(ctx context.Context, id uuid.UUID) (string, error) {
	token := routes.NewShareToken()
	_, err := s.DB.Exec(ctx, `UPDATE collections SET share_token = $2 WHERE id = $1`, id, token)
	return token, err
}

// AddItem appends a route or journey (kind "route" or "journey").
func (s *Store) AddItem(ctx context.Context, id uuid.UUID, kind string, target uuid.UUID, note string, by uuid.UUID) error {
	col := "route_id"
	if kind == "journey" {
		col = "journey_id"
	}
	return s.tx(ctx, id, func(tx pgx.Tx) error {
		var n int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM collection_items WHERE collection_id = $1`, id).Scan(&n); err != nil {
			return err
		}
		if n >= MaxItems {
			return ErrFull
		}
		_, err := tx.Exec(ctx, `INSERT INTO collection_items (collection_id, position, `+col+`, note, added_by)
			VALUES ($1, $2, $3, $4, $5)`, id, n, target, note, by)
		if pgErr := (*pgconn.PgError)(nil); errors.As(err, &pgErr) && pgErr.Code == "23505" { // unique_violation
			return ErrDuplicate
		}
		return err
	})
}

// ItemPatch holds the item fields to change; nil leaves a field alone.
type ItemPatch struct {
	Note     *string
	Position *int // 0-based; others shift to make room
}

// UpdateItem changes an item's note or moves it.
func (s *Store) UpdateItem(ctx context.Context, id, itemID uuid.UUID, p ItemPatch) error {
	return s.tx(ctx, id, func(tx pgx.Tx) error {
		var pos, n int
		err := tx.QueryRow(ctx, `SELECT position, (SELECT count(*) FROM collection_items WHERE collection_id = $1)
			FROM collection_items WHERE id = $2 AND collection_id = $1 FOR UPDATE`, id, itemID).Scan(&pos, &n)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrItemNotFound
		}
		if err != nil {
			return err
		}
		if p.Note != nil {
			if _, err := tx.Exec(ctx, `UPDATE collection_items SET note = $2 WHERE id = $1`, itemID, *p.Note); err != nil {
				return err
			}
		}
		if p.Position == nil {
			return nil
		}
		to := min(max(*p.Position, 0), n-1)
		switch {
		case to > pos:
			_, err = tx.Exec(ctx, `UPDATE collection_items SET position = position - 1
				WHERE collection_id = $1 AND position > $2 AND position <= $3`, id, pos, to)
		case to < pos:
			_, err = tx.Exec(ctx, `UPDATE collection_items SET position = position + 1
				WHERE collection_id = $1 AND position >= $3 AND position < $2`, id, pos, to)
		}
		if err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `UPDATE collection_items SET position = $2 WHERE id = $1`, itemID, to)
		return err
	})
}

// DeleteItem removes an item. The trigger collection_items_renumber closes
// the gap in positions.
func (s *Store) DeleteItem(ctx context.Context, id, itemID uuid.UUID) error {
	return s.tx(ctx, id, func(tx pgx.Tx) error {
		res, err := tx.Exec(ctx, `DELETE FROM collection_items WHERE id = $2 AND collection_id = $1`, id, itemID)
		if err != nil {
			return err
		}
		if res.RowsAffected() == 0 {
			return ErrItemNotFound
		}
		return nil
	})
}

// tx runs fn in a transaction and marks the collection as changed. Marking
// it first locks it: changes to its items (counted, then shifted) go one
// after the other.
func (s *Store) tx(ctx context.Context, id uuid.UUID, fn func(pgx.Tx) error) error {
	return pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		res, err := tx.Exec(ctx, `UPDATE collections SET updated_at = now() WHERE id = $1`, id)
		if err != nil {
			return err
		}
		if res.RowsAffected() == 0 { // deleted since it was loaded
			return ErrNotFound
		}
		return fn(tx)
	})
}
