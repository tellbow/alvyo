// Package restore copies part of a backup back: a user's routes, journeys
// and collections, or one of them, from a dump loaded into a scratch
// database (docs/restore.md) into the live one (feedback issue 74).
//
// Only rows missing in the live database are added; what is there stays.
// A row whose other end is gone (a like from a deleted account, an item of
// a collection whose route is gone) is left out, and so is a photo whose
// file is no longer on disk.
package restore

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// What names what to restore: Kind user (ID is the username), route,
// journey or collection.
type What struct {
	Kind, ID string
}

// Count is how many rows of a table were added and left out.
type Count struct {
	Table         string
	Added, Missed int
}

// Restorer reads From (the scratch database) and writes To (the live one).
type Restorer struct {
	From, To  *pgxpool.Pool
	PhotoFile func(id uuid.UUID) string // the path of a photo's large file
}

// ErrNotFound means the backup does not hold what was asked for, or the
// user is not in the live database (restore the account first).
var ErrNotFound = errors.New("restore: not found")

// sets are the ids to restore, read from the backup.
type sets struct {
	routes, journeys, collections, stages []uuid.UUID
}

// tables in the order their rows can go in, each with the rows of the
// sets that belong to it (p.r routes, p.j journeys, p.c collections, p.s stages).
var tables = []struct{ name, where string }{
	{"journeys", "id = ANY(p.j)"},
	{"routes", "id = ANY(p.r)"},
	{"stages", "id = ANY(p.s)"},
	{"collections", "id = ANY(p.c)"},
	{"grants", "route_id = ANY(p.r) OR journey_id = ANY(p.j) OR collection_id = ANY(p.c)"},
	{"stage_people", "stage_id = ANY(p.s)"},
	{"collection_items", "collection_id = ANY(p.c) OR route_id = ANY(p.r) OR journey_id = ANY(p.j)"},
	{"likes", "route_id = ANY(p.r) OR journey_id = ANY(p.j)"},
	{"comments", "route_id = ANY(p.r) OR journey_id = ANY(p.j)"},
	{"photos", "route_id = ANY(p.r) OR journey_id = ANY(p.j)"},
	{"route_revisions", "route_id = ANY(p.r)"},
	{"done_marks", "route_id = ANY(p.r) OR journey_id = ANY(p.j)"},
	{"route_travel", "route_id = ANY(p.r)"},
	{"journey_travel", "journey_id = ANY(p.j)"},
	{"journey_reminders", "journey_id = ANY(p.j)"},
	{"journey_reminders_off", "journey_id = ANY(p.j)"},
}

// Run restores w; with apply false it only counts and changes nothing.
func (r *Restorer) Run(ctx context.Context, w What, apply bool) ([]Count, error) {
	s, err := r.sets(ctx, w)
	if err != nil {
		return nil, err
	}
	tx, err := r.To.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	// Deferrable keys (a stage's position) checked at once, per row.
	if _, err := tx.Exec(ctx, `SET CONSTRAINTS ALL IMMEDIATE`); err != nil {
		return nil, err
	}
	var out []Count
	for _, t := range tables {
		c, err := r.copyTable(ctx, tx, t.name, t.where, s)
		if err != nil {
			return nil, fmt.Errorf("restore: %s: %w", t.name, err)
		}
		out = append(out, c)
	}
	if !apply {
		return out, nil
	}
	return out, tx.Commit(ctx)
}

func (r *Restorer) sets(ctx context.Context, w What) (sets, error) {
	var s sets
	var err error
	ids := func(q string, args ...any) []uuid.UUID {
		if err != nil {
			return nil
		}
		var rows pgx.Rows
		if rows, err = r.From.Query(ctx, q, args...); err != nil {
			return nil
		}
		var got []uuid.UUID
		got, err = pgx.CollectRows(rows, pgx.RowTo[uuid.UUID])
		return got
	}
	switch w.Kind {
	case "user":
		// The account must be in both; ids stay the same across a dump.
		var user uuid.UUID
		if err := r.From.QueryRow(ctx, `SELECT id FROM users WHERE username = $1`, w.ID).Scan(&user); err != nil {
			return s, notFound(err)
		}
		if err := r.To.QueryRow(ctx, `SELECT id FROM users WHERE id = $1`, user).Scan(&user); err != nil {
			return s, notFound(err)
		}
		s.journeys = ids(`SELECT id FROM journeys WHERE owner_id = $1`, user)
		s.routes = ids(`SELECT id FROM routes WHERE owner_id = $1 OR journey_id = ANY($2)`, user, s.journeys)
		s.collections = ids(`SELECT id FROM collections WHERE owner_id = $1`, user)
	case "route", "journey", "collection":
		id, perr := uuid.Parse(w.ID)
		if perr != nil {
			return s, ErrNotFound
		}
		var found bool
		if err := r.From.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM `+w.Kind+`s WHERE id = $1)`, id).Scan(&found); err != nil || !found {
			return s, errors.Join(ErrNotFound, err)
		}
		switch w.Kind {
		case "route":
			s.routes = []uuid.UUID{id}
		case "journey":
			s.journeys = []uuid.UUID{id}
			s.routes = ids(`SELECT id FROM routes WHERE journey_id = $1`, id)
		case "collection":
			s.collections = []uuid.UUID{id}
		}
	default:
		return s, fmt.Errorf("restore: unknown kind %q", w.Kind)
	}
	s.stages = ids(`SELECT id FROM stages WHERE journey_id = ANY($1)`, s.journeys)
	return s, err
}

// copyTable adds the table's rows of s that are missing, one by one, each
// in a savepoint, so that a row whose other end is gone is left out.
// Values go through their text form, which every type reads back as it was
// (geometries, arrays, JSON); columns the backup lacks get their default.
func (r *Restorer) copyTable(ctx context.Context, tx pgx.Tx, table, where string, s sets) (Count, error) {
	c := Count{Table: table}
	cols, types, err := columns(ctx, tx, r.From, table)
	if err != nil {
		return c, err
	}
	sel := make([]string, len(cols))
	params := make([]string, len(cols))
	for i, col := range cols {
		sel[i] = col + "::text"
		params[i] = fmt.Sprintf("$%d::text::%s", i+1, types[i])
	}
	order := ""
	if contains(cols, "created_at") {
		order = " ORDER BY created_at" // replies after what they reply to, recordings after their plan
	}
	rows, err := r.From.Query(ctx, `SELECT `+strings.Join(sel, ", ")+` FROM `+table+`,
		(SELECT $1::uuid[] AS r, $2::uuid[] AS j, $3::uuid[] AS c, $4::uuid[] AS s) p WHERE `+where+order,
		s.routes, s.journeys, s.collections, s.stages)
	if err != nil {
		return c, err
	}
	all, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) ([]any, error) {
		vals := make([]*string, len(cols))
		ptrs := make([]any, len(cols))
		for i := range vals {
			ptrs[i] = &vals[i]
		}
		if err := row.Scan(ptrs...); err != nil {
			return nil, err
		}
		out := make([]any, len(vals))
		for i, v := range vals {
			out[i] = v
		}
		return out, nil
	})
	if err != nil {
		return c, err
	}
	insert := `INSERT INTO ` + table + ` (` + strings.Join(cols, ", ") + `) VALUES (` + strings.Join(params, ", ") + `)`
	idCol := index(cols, "id")
	for _, vals := range all {
		if table == "photos" && r.PhotoFile != nil && idCol >= 0 {
			var there bool
			if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM photos WHERE id = $1::uuid)`, vals[idCol]).Scan(&there); err != nil {
				return c, err
			}
			if there {
				continue
			}
			if _, err := os.Stat(r.PhotoFile(uuid.MustParse(*vals[idCol].(*string)))); err != nil {
				c.Missed++ // its file is gone: restore it first (docs/restore.md)
				continue
			}
		}
		if _, err := tx.Exec(ctx, "SAVEPOINT row"); err != nil {
			return c, err
		}
		_, err := tx.Exec(ctx, insert, vals...)
		var pe *pgconn.PgError
		switch {
		case errors.As(err, &pe) && (pe.Code == "23503" || pe.Code == "23505" || pe.Code == "23514"):
			// Its other end gone, no longer allowed, or a key taken: by
			// itself (already there) or by another row (a stage's position).
			if _, err := tx.Exec(ctx, "ROLLBACK TO SAVEPOINT row"); err != nil {
				return c, err
			}
			there := pe.Code == "23505" && idCol < 0 // likes, marks: the key is the row
			if pe.Code == "23505" && idCol >= 0 {
				if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM `+table+` WHERE id = $1::uuid)`, vals[idCol]).Scan(&there); err != nil {
					return c, err
				}
			}
			if !there {
				c.Missed++
			}
			continue
		case err != nil:
			return c, err
		}
		c.Added++
		// A restored photo's file must stay: it may wait in the trash.
		if table == "photos" && idCol >= 0 {
			if _, err := tx.Exec(ctx, `DELETE FROM photo_trash WHERE id = $1::uuid`, vals[idCol]); err != nil {
				return c, err
			}
		}
		if _, err := tx.Exec(ctx, "RELEASE SAVEPOINT row"); err != nil {
			return c, err
		}
	}
	return c, nil
}

// columns are the table's columns both databases have (not generated), with
// their types in the live one.
func columns(ctx context.Context, live pgx.Tx, backup *pgxpool.Pool, table string) ([]string, []string, error) {
	const q = `SELECT a.attname, format_type(a.atttypid, a.atttypmod) FROM pg_attribute a
		WHERE a.attrelid = $1::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attgenerated = ''
		ORDER BY a.attnum`
	liveCols, err := colTypes(ctx, live, q, table)
	if err != nil {
		return nil, nil, err
	}
	backupCols, err := colTypes(ctx, backup, q, table)
	if err != nil {
		return nil, nil, err
	}
	have := map[string]bool{}
	for _, c := range backupCols {
		have[c[0]] = true
	}
	var cols, types []string
	for _, c := range liveCols {
		if have[c[0]] {
			cols, types = append(cols, `"`+c[0]+`"`), append(types, c[1])
		}
	}
	return cols, types, nil
}

type querier interface {
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
}

func colTypes(ctx context.Context, db querier, q, table string) ([][2]string, error) {
	rows, err := db.Query(ctx, q, table)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(row pgx.CollectableRow) ([2]string, error) {
		var c [2]string
		return c, row.Scan(&c[0], &c[1])
	})
}

func contains(cols []string, name string) bool { return index(cols, name) >= 0 }

func index(cols []string, name string) int {
	for i, c := range cols {
		if c == `"`+name+`"` {
			return i
		}
	}
	return -1
}

func notFound(err error) error {
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	return err
}
