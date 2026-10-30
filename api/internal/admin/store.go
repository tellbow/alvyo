package admin

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Errors of the admin portal's actions.
var (
	ErrStaff    = errors.New("moderators and admins cannot be banned")
	ErrNoChange = errors.New("nothing to change")
	ErrUndo     = errors.New("cannot be undone")
	ErrLater    = errors.New("changed again since: undo the later change first")
)

// Store runs the admin portal's actions and keeps their log, «Verlauf»
// (feedback issues 70, 72).
type Store struct {
	DB *pgxpool.Pool
	// For «System»: GraphHopper's address, the swissALTI3D tiles ("" without)
	// and the outside services to check.
	GraphHopper string
	AltiDir     string
	Probes      []Probe
	Kube        *Kube // starts cron jobs; nil outside the cluster
}

// Change is a row as it was before an action: what an undo writes back.
type Change struct {
	Table string          `json:"table"`
	ID    uuid.UUID       `json:"id"`
	Set   json.RawMessage `json:"set"`
}

// undoable is what an undo may write back, per table.
var undoable = map[string][]string{
	"users":       {"banned_at", "role"},
	"routes":      {"visibility"},
	"journeys":    {"visibility"},
	"collections": {"visibility"},
}

// Snapshot returns the columns of a row, before an action changes them.
func Snapshot(ctx context.Context, tx pgx.Tx, table string, id uuid.UUID, cols ...string) (Change, error) {
	pairs := make([]string, len(cols))
	for i, c := range cols {
		pairs[i] = fmt.Sprintf("'%s', %s", c, c)
	}
	c := Change{Table: table, ID: id}
	err := tx.QueryRow(ctx, `SELECT jsonb_build_object(`+strings.Join(pairs, ", ")+`) FROM `+table+` WHERE id = $1`, id).Scan(&c.Set)
	return c, notFound(err)
}

// BanSnapshot is what BanUser changes: the user's ban and the visibility of
// their items that others could see.
func BanSnapshot(ctx context.Context, tx pgx.Tx, user uuid.UUID) ([]Change, error) {
	u, err := Snapshot(ctx, tx, "users", user, "banned_at")
	if err != nil {
		return nil, err
	}
	out := []Change{u}
	rows, err := tx.Query(ctx, `
		SELECT 'routes', id, jsonb_build_object('visibility', visibility) FROM routes WHERE owner_id = $1 AND visibility <> 'private'
		UNION ALL SELECT 'journeys', id, jsonb_build_object('visibility', visibility) FROM journeys WHERE owner_id = $1 AND visibility <> 'private'
		UNION ALL SELECT 'collections', id, jsonb_build_object('visibility', visibility) FROM collections WHERE owner_id = $1 AND visibility <> 'private'`, user)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var c Change
		if err := rows.Scan(&c.Table, &c.ID, &c.Set); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// Entry is one action in the log.
type Entry struct {
	Area       string // meldungen, nutzer, inhalte or system
	Title      string // in plain German, for «Verlauf»
	TargetKind string // user, route, journey, collection, comment, photo
	TargetID   uuid.UUID
	Undo       []Change // nil: cannot be undone
}

// Record logs an action of actor inside its transaction.
func Record(ctx context.Context, tx pgx.Tx, actor uuid.UUID, e Entry) (uuid.UUID, error) {
	var undo []byte
	if e.Undo != nil {
		var err error
		if undo, err = json.Marshal(e.Undo); err != nil {
			return uuid.Nil, err
		}
	}
	var id uuid.UUID
	err := tx.QueryRow(ctx, `INSERT INTO admin_log (actor_id, area, title, target_kind, target_id, undo)
		VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`, actor, e.Area, e.Title, e.TargetKind, e.TargetID, undo).Scan(&id)
	return id, err
}

// do runs fn in a transaction and logs what it returns.
func (s *Store) do(ctx context.Context, actor uuid.UUID, fn func(tx pgx.Tx) (Entry, error)) (uuid.UUID, error) {
	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return uuid.Nil, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	e, err := fn(tx)
	if err != nil {
		return uuid.Nil, err
	}
	id, err := Record(ctx, tx, actor, e)
	if err != nil {
		return uuid.Nil, err
	}
	return id, tx.Commit(ctx)
}

// lockUser returns the user's name, role and whether they are banned.
func lockUser(ctx context.Context, tx pgx.Tx, id uuid.UUID) (name, role string, banned bool, err error) {
	err = tx.QueryRow(ctx, `SELECT username, role, banned_at IS NOT NULL FROM users WHERE id = $1 FOR UPDATE`, id).
		Scan(&name, &role, &banned)
	return name, role, banned, notFound(err)
}

// Ban bans a user (see BanUser); not staff.
func (s *Store) Ban(ctx context.Context, actor, user uuid.UUID) (uuid.UUID, error) {
	return s.do(ctx, actor, func(tx pgx.Tx) (Entry, error) {
		name, role, banned, err := lockUser(ctx, tx, user)
		switch {
		case err != nil:
			return Entry{}, err
		case role != "user":
			return Entry{}, ErrStaff
		case banned:
			return Entry{}, ErrNoChange
		}
		undo, err := BanSnapshot(ctx, tx, user)
		if err != nil {
			return Entry{}, err
		}
		return Entry{Area: "nutzer", Title: "@" + name + " gesperrt", TargetKind: "user", TargetID: user, Undo: undo},
			BanUser(ctx, tx, user)
	})
}

// Unban lets a user log in again; their items stay private.
func (s *Store) Unban(ctx context.Context, actor, user uuid.UUID) (uuid.UUID, error) {
	return s.do(ctx, actor, func(tx pgx.Tx) (Entry, error) {
		name, _, banned, err := lockUser(ctx, tx, user)
		if err != nil {
			return Entry{}, err
		}
		if !banned {
			return Entry{}, ErrNoChange
		}
		before, err := Snapshot(ctx, tx, "users", user, "banned_at")
		if err != nil {
			return Entry{}, err
		}
		_, err = tx.Exec(ctx, `UPDATE users SET banned_at = NULL WHERE id = $1`, user)
		return Entry{Area: "nutzer", Title: "@" + name + " entsperrt", TargetKind: "user", TargetID: user, Undo: []Change{before}}, err
	})
}

// SetRole gives a user the role user, moderator or admin.
func (s *Store) SetRole(ctx context.Context, actor, user uuid.UUID, role string) (uuid.UUID, error) {
	return s.do(ctx, actor, func(tx pgx.Tx) (Entry, error) {
		name, old, _, err := lockUser(ctx, tx, user)
		if err != nil {
			return Entry{}, err
		}
		if old == role {
			return Entry{}, ErrNoChange
		}
		before, err := Snapshot(ctx, tx, "users", user, "role")
		if err != nil {
			return Entry{}, err
		}
		_, err = tx.Exec(ctx, `UPDATE users SET role = $2 WHERE id = $1`, user, role)
		return Entry{Area: "nutzer", Title: "@" + name + ": Rolle " + old + " → " + role, TargetKind: "user", TargetID: user,
			Undo: []Change{before}}, err
	})
}

// EndSessions logs a user out everywhere; not undoable.
func (s *Store) EndSessions(ctx context.Context, actor, user uuid.UUID) (uuid.UUID, error) {
	return s.do(ctx, actor, func(tx pgx.Tx) (Entry, error) {
		name, _, _, err := lockUser(ctx, tx, user)
		if err != nil {
			return Entry{}, err
		}
		_, err = tx.Exec(ctx, `DELETE FROM sessions WHERE user_id = $1`, user)
		return Entry{Area: "nutzer", Title: "@" + name + " überall abgemeldet", TargetKind: "user", TargetID: user}, err
	})
}

// LogVerificationSent records that a new confirmation e-mail went out.
func (s *Store) LogVerificationSent(ctx context.Context, actor, user uuid.UUID) (uuid.UUID, error) {
	return s.do(ctx, actor, func(tx pgx.Tx) (Entry, error) {
		name, _, _, err := lockUser(ctx, tx, user)
		return Entry{Area: "nutzer", Title: "Bestätigungs-E-Mail an @" + name, TargetKind: "user", TargetID: user}, err
	})
}

// Unpublish makes a route, journey or collection private.
func (s *Store) Unpublish(ctx context.Context, actor uuid.UUID, kind string, id uuid.UUID) (uuid.UUID, error) {
	table, ok := map[string]string{"route": "routes", "journey": "journeys", "collection": "collections"}[kind]
	if !ok {
		return uuid.Nil, ErrNotFound
	}
	return s.do(ctx, actor, func(tx pgx.Tx) (Entry, error) {
		var title, visibility string
		err := tx.QueryRow(ctx, `SELECT title, visibility FROM `+table+` WHERE id = $1 FOR UPDATE`, id).Scan(&title, &visibility)
		if err != nil {
			return Entry{}, notFound(err)
		}
		if visibility == "private" {
			return Entry{}, ErrNoChange
		}
		before, err := Snapshot(ctx, tx, table, id, "visibility")
		if err != nil {
			return Entry{}, err
		}
		_, err = tx.Exec(ctx, `UPDATE `+table+` SET visibility = 'private', version = version + 1, updated_at = now() WHERE id = $1`, id)
		return Entry{Area: "inhalte", Title: "«" + title + "» privat gemacht", TargetKind: kind, TargetID: id, Undo: []Change{before}}, err
	})
}

// ErrRole means only admins change roles, and undo a change of one.
var ErrRole = errors.New("only admins change roles")

// Undo writes back the rows as they were before the action id, unless one
// of them was changed by a later action that is not undone. Without
// roles, a change of role is refused (ErrRole).
func (s *Store) Undo(ctx context.Context, actor, id uuid.UUID, roles bool) error {
	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	var at time.Time
	var raw []byte
	var undone bool
	err = tx.QueryRow(ctx, `SELECT at, undo, undone_at IS NOT NULL FROM admin_log WHERE id = $1 FOR UPDATE`, id).Scan(&at, &raw, &undone)
	if err != nil {
		return notFound(err)
	}
	if raw == nil || undone {
		return ErrUndo
	}
	var changes []Change
	if err := json.Unmarshal(raw, &changes); err != nil {
		return err
	}
	ids := make([]uuid.UUID, len(changes))
	for i, c := range changes {
		ids[i] = c.ID
		var set map[string]json.RawMessage
		if err := json.Unmarshal(c.Set, &set); err != nil {
			return err
		}
		if _, ok := set["role"]; ok && !roles {
			return ErrRole
		}
	}
	var later bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM admin_log
		WHERE target_id = ANY($1) AND at > $2 AND id <> $3 AND undone_at IS NULL)`, ids, at, id).Scan(&later); err != nil {
		return err
	}
	if later {
		return ErrLater
	}
	for _, c := range changes {
		cols, ok := undoable[c.Table]
		if !ok {
			return fmt.Errorf("admin: undo of table %q", c.Table)
		}
		set := make([]string, len(cols))
		for i, col := range cols {
			// Columns the snapshot lacks keep their value.
			set[i] = fmt.Sprintf("%s = CASE WHEN $2::jsonb ? '%s' THEN r.%s ELSE t.%s END", col, col, col, col)
		}
		if c.Table != "users" {
			set = append(set, "version = t.version + 1", "updated_at = now()")
		}
		if _, err := tx.Exec(ctx, `UPDATE `+c.Table+` t SET `+strings.Join(set, ", ")+`
			FROM jsonb_populate_record(NULL::`+c.Table+`, $2) r WHERE t.id = $1`, c.ID, []byte(c.Set)); err != nil {
			return err
		}
	}
	if _, err := tx.Exec(ctx, `UPDATE admin_log SET undone_at = now(), undone_by = $2 WHERE id = $1`, id, actor); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// LogEntry is an action in «Verlauf».
type LogEntry struct {
	ID         string     `json:"id" format:"uuid"`
	At         time.Time  `json:"at"`
	Actor      string     `json:"actor" doc:"Username; empty when the account is gone"`
	Area       string     `json:"area" enum:"meldungen,nutzer,inhalte,system"`
	Title      string     `json:"title"`
	TargetKind string     `json:"target_kind"`
	TargetID   string     `json:"target_id" format:"uuid"`
	Undoable   bool       `json:"undoable" doc:"It can be undone, unless changed again since"`
	UndoneAt   *time.Time `json:"undone_at,omitempty"`
}

// Log returns the newest actions, of one area or all ("").
func (s *Store) Log(ctx context.Context, area string, limit int) ([]LogEntry, error) {
	rows, err := s.DB.Query(ctx, `SELECT l.id, l.at, coalesce(u.username::text, ''), l.area, l.title, l.target_kind, l.target_id,
			l.undo IS NOT NULL AND l.undone_at IS NULL, l.undone_at
		FROM admin_log l LEFT JOIN users u ON u.id = l.actor_id
		WHERE $1 = '' OR l.area = $1 ORDER BY l.at DESC LIMIT $2`, area, limit)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (LogEntry, error) {
		var e LogEntry
		var id, target uuid.UUID
		err := r.Scan(&id, &e.At, &e.Actor, &e.Area, &e.Title, &e.TargetKind, &target, &e.Undoable, &e.UndoneAt)
		e.ID, e.TargetID = id.String(), target.String()
		return e, err
	})
}

// User is an account as the admin portal lists it.
type User struct {
	ID            string     `json:"id" format:"uuid"`
	Username      string     `json:"username"`
	DisplayName   string     `json:"display_name"`
	Email         string     `json:"email"`
	EmailVerified bool       `json:"email_verified"`
	Role          string     `json:"role" enum:"user,moderator,admin"`
	BannedAt      *time.Time `json:"banned_at,omitempty"`
	CreatedAt     time.Time  `json:"created_at"`
	LastSeenAt    *time.Time `json:"last_seen_at,omitempty" doc:"When one of their sessions was last used, to a day"`
	Routes        int        `json:"routes"`
	Journeys      int        `json:"journeys"`
	Collections   int        `json:"collections"`
	Sessions      int        `json:"sessions"`
}

// seen is when a session was last used: last_seen_at is written when it is
// extended (once a day at most), a new one counts from its start.
const seen = `coalesce(last_seen_at, created_at)`

// UserCounts are the totals over all accounts that match a search.
type UserCounts struct {
	Total  int `json:"total"`
	Active int `json:"active" doc:"Seen in the last 30 days"`
	Banned int `json:"banned"`
}

// userMatch is the search over username, display name and e-mail address;
// $1 is the term, empty for all. Not the system's own accounts at
// alvyo.invalid (wanderland, the owner of the official routes).
const userMatch = `u.email NOT LIKE '%@alvyo.invalid' AND ($1 = '' OR strpos(lower(u.username::text), lower($1)) > 0 OR strpos(lower(u.display_name), lower($1)) > 0
	OR strpos(lower(u.email::text), lower($1)) > 0)`

// Users finds accounts by name, display name or e-mail address (all for an
// empty query), newest first, limit from offset, with the totals.
func (s *Store) Users(ctx context.Context, q string, limit, offset int) ([]User, UserCounts, error) {
	q = strings.TrimSpace(q)
	var c UserCounts
	if err := s.DB.QueryRow(ctx, `SELECT count(*),
			count(*) FILTER (WHERE EXISTS (SELECT 1 FROM sessions WHERE user_id = u.id AND `+seen+` > now() - interval '30 days')),
			count(*) FILTER (WHERE u.banned_at IS NOT NULL)
		FROM users u WHERE `+userMatch, q).Scan(&c.Total, &c.Active, &c.Banned); err != nil {
		return nil, c, err
	}
	rows, err := s.DB.Query(ctx, `SELECT u.id, u.username, u.display_name, u.email, u.email_verified_at IS NOT NULL, u.role,
			u.banned_at, u.created_at,
			(SELECT max(`+seen+`) FROM sessions WHERE user_id = u.id),
			(SELECT count(*) FROM routes WHERE owner_id = u.id AND journey_id IS NULL),
			(SELECT count(*) FROM journeys WHERE owner_id = u.id),
			(SELECT count(*) FROM collections WHERE owner_id = u.id),
			(SELECT count(*) FROM sessions WHERE user_id = u.id AND expires_at > now())
		FROM users u WHERE `+userMatch+`
		ORDER BY u.created_at DESC, u.id LIMIT $2 OFFSET $3`, q, limit, offset)
	if err != nil {
		return nil, c, err
	}
	users, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (User, error) {
		var u User
		var id uuid.UUID
		err := r.Scan(&id, &u.Username, &u.DisplayName, &u.Email, &u.EmailVerified, &u.Role, &u.BannedAt, &u.CreatedAt,
			&u.LastSeenAt, &u.Routes, &u.Journeys, &u.Collections, &u.Sessions)
		u.ID = id.String()
		return u, err
	})
	return users, c, err
}

// Item is a route, journey or collection as the admin portal lists it.
type Item struct {
	Kind       string    `json:"kind" enum:"route,journey,collection"`
	ID         string    `json:"id" format:"uuid"`
	Title      string    `json:"title"`
	Owner      string    `json:"owner"`
	Visibility string    `json:"visibility" enum:"private,unlisted,public"`
	UpdatedAt  time.Time `json:"updated_at"`
}

var anID = regexp.MustCompile(`[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}`)

// Items finds routes (not stages), journeys and collections by an id or a
// link holding one, else by their owner's username or a word of the title.
func (s *Store) Items(ctx context.Context, q string, limit int) ([]Item, error) {
	q = strings.TrimPrefix(strings.TrimSpace(q), "@")
	var id *uuid.UUID
	if m := anID.FindString(q); m != "" {
		u := uuid.MustParse(m)
		id = &u
	}
	rows, err := s.DB.Query(ctx, `
		WITH items AS (
			SELECT 'route' AS kind, id, title, owner_id, visibility, updated_at FROM routes WHERE journey_id IS NULL
			UNION ALL SELECT 'journey', id, title, owner_id, visibility, updated_at FROM journeys
			UNION ALL SELECT 'collection', id, title, owner_id, visibility, updated_at FROM collections)
		SELECT i.kind, i.id, i.title, u.username, i.visibility, i.updated_at
		FROM items i JOIN users u ON u.id = i.owner_id
		WHERE CASE WHEN $1::uuid IS NOT NULL THEN i.id = $1
			ELSE u.username = $2 OR ($2 <> '' AND strpos(lower(i.title), lower($2)) > 0) END
		ORDER BY i.updated_at DESC LIMIT $3`, id, q, limit)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (Item, error) {
		var it Item
		var id uuid.UUID
		err := r.Scan(&it.Kind, &id, &it.Title, &it.Owner, &it.Visibility, &it.UpdatedAt)
		it.ID = id.String()
		return it, err
	})
}
