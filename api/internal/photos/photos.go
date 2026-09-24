package photos

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Limits on the number of photos.
const (
	MaxPerItem = 100
	MaxPerUser = 1000
	// pinM is how close to the route a photo must be taken to be pinned.
	pinM = 500
)

// Errors of the store.
var (
	ErrNotFound = errors.New("photos: not found")
	ErrLimit    = errors.New("photos: too many photos")
	ErrOrder    = errors.New("photos: the order must list every photo once")
)

// Target is the route or journey photos belong to.
type Target struct {
	Kind string // "route" or "journey"
	ID   uuid.UUID
}

func (t Target) column() string { return t.Kind + "_id" }

// Photo is a stored photo.
type Photo struct {
	ID       string     `json:"id" format:"uuid"`
	Caption  string     `json:"caption"`
	Width    int        `json:"width"`
	Height   int        `json:"height"`
	TakenAt  *time.Time `json:"taken_at,omitempty"`
	Pin      []float64  `json:"pin,omitempty" doc:"Where it was taken (lon, lat) when that is along the route"`
	Uploader string     `json:"uploader"`
}

// Store keeps photo records in the database and their files on disk.
type Store struct {
	DB    *pgxpool.Pool
	Files *Files
}

// List returns the photos of t in gallery order.
func (s *Store) List(ctx context.Context, t Target) ([]Photo, error) {
	rows, err := s.DB.Query(ctx, `SELECT p.id, p.caption, p.width, p.height, p.taken_at, ST_X(p.geom), ST_Y(p.geom), u.username
		FROM photos p JOIN users u ON u.id = p.uploader_id
		WHERE p.`+t.column()+` = $1 ORDER BY p.position, p.id`, t.ID)
	if err != nil {
		return nil, fmt.Errorf("photos: list: %w", err)
	}
	defer rows.Close()
	out := []Photo{}
	for rows.Next() {
		var p Photo
		var id uuid.UUID
		var lon, lat *float64
		if err := rows.Scan(&id, &p.Caption, &p.Width, &p.Height, &p.TakenAt, &lon, &lat, &p.Uploader); err != nil {
			return nil, err
		}
		p.ID = id.String()
		if lon != nil && lat != nil {
			p.Pin = []float64{*lon, *lat}
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// Add stores a processed upload as the last photo of t. Its position is
// kept only if it lies within 500 m of the route (of any stage for a
// journey).
func (s *Store) Add(ctx context.Context, t Target, uploader uuid.UUID, p Processed, caption string) error {
	var onItem, byUser int
	if err := s.DB.QueryRow(ctx, `SELECT (SELECT count(*) FROM photos WHERE `+t.column()+` = $1),
		(SELECT count(*) FROM photos WHERE uploader_id = $2)`, t.ID, uploader).Scan(&onItem, &byUser); err != nil {
		return err
	}
	if onItem >= MaxPerItem || byUser >= MaxPerUser {
		return ErrLimit
	}
	id, err := uuid.NewV7()
	if err != nil {
		return err
	}
	if err := s.Files.Write(id, p); err != nil {
		return fmt.Errorf("photos: write: %w", err)
	}
	_, err = s.DB.Exec(ctx, `INSERT INTO photos (id, uploader_id, `+t.column()+`, caption, width, height, bytes, taken_at, geom, position)
		SELECT $1, $2, $3, $4, $5, $6, $7, $8,
			CASE WHEN EXISTS (
				SELECT 1 FROM routes r
				WHERE (r.id = $3 OR r.id IN (SELECT st.route_id FROM stages st WHERE st.journey_id = $3))
					AND ST_DWithin(r.geom::geography, ST_Point($9, $10, 4326)::geography, $11)
			) THEN ST_Point($9, $10, 4326) END,
			coalesce((SELECT max(position) FROM photos WHERE `+t.column()+` = $3), 0) + 1`,
		id, uploader, t.ID, caption, p.Width, p.Height, len(p.Large)+len(p.Thumb), p.TakenAt, p.Lon, p.Lat, pinM)
	if err != nil {
		if rmErr := s.Files.Remove(id); rmErr != nil {
			slog.ErrorContext(ctx, "photo files", "err", rmErr)
		}
		return fmt.Errorf("photos: add: %w", err)
	}
	return nil
}

// Update changes the caption (if not nil) and removes the pin (if unpin).
func (s *Store) Update(ctx context.Context, t Target, id uuid.UUID, caption *string, unpin bool) error {
	res, err := s.DB.Exec(ctx, `UPDATE photos SET caption = coalesce($3, caption),
		geom = CASE WHEN $4 THEN NULL ELSE geom END
		WHERE id = $1 AND `+t.column()+` = $2`, id, t.ID, caption, unpin)
	if err == nil && res.RowsAffected() == 0 {
		return ErrNotFound
	}
	return err
}

// Order puts the photos of t in the order of ids, which must list each once;
// otherwise nothing changes.
func (s *Store) Order(ctx context.Context, t Target, ids []uuid.UUID) error {
	seen := map[uuid.UUID]bool{}
	for _, id := range ids {
		if seen[id] {
			return ErrOrder
		}
		seen[id] = true
	}
	if len(ids) == 0 {
		return ErrOrder
	}
	return pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		res, err := tx.Exec(ctx, `UPDATE photos p SET position = o.n
			FROM unnest($2::uuid[]) WITH ORDINALITY AS o(id, n)
			WHERE p.id = o.id AND p.`+t.column()+` = $1
				AND (SELECT count(*) FROM photos WHERE `+t.column()+` = $1) = cardinality($2::uuid[])`, t.ID, ids)
		if err != nil {
			return err
		}
		if int(res.RowsAffected()) != len(ids) {
			return ErrOrder // someone else's photo among them: rolled back
		}
		return nil
	})
}

// Delete removes a photo of t; its files go right away.
func (s *Store) Delete(ctx context.Context, t Target, id uuid.UUID) error {
	res, err := s.DB.Exec(ctx, `DELETE FROM photos WHERE id = $1 AND `+t.column()+` = $2`, id, t.ID)
	if err != nil {
		return err
	}
	if res.RowsAffected() == 0 {
		return ErrNotFound
	}
	if err := s.Files.Remove(id); err != nil {
		slog.ErrorContext(ctx, "photo files", "err", err) // the trash sweep retries
	}
	return nil
}

// Owner returns what a photo belongs to, and whether it has an open report
// (moderators may then see it).
func (s *Store) Owner(ctx context.Context, id uuid.UUID) (t Target, reported bool, err error) {
	var route, journey *uuid.UUID
	err = s.DB.QueryRow(ctx, `SELECT route_id, journey_id,
		EXISTS (SELECT 1 FROM reports WHERE photo_id = photos.id AND resolved_at IS NULL)
		FROM photos WHERE id = $1`, id).Scan(&route, &journey, &reported)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		return t, false, ErrNotFound
	case err != nil:
		return t, false, err
	case route != nil:
		return Target{Kind: "route", ID: *route}, reported, nil
	default:
		return Target{Kind: "journey", ID: *journey}, reported, nil
	}
}

// Sweep removes the files of deleted photos, including those deleted with
// their route, journey or account.
func (s *Store) Sweep(ctx context.Context) error {
	rows, err := s.DB.Query(ctx, `SELECT id FROM photo_trash ORDER BY deleted_at LIMIT 1000`)
	if err != nil {
		return err
	}
	ids, err := pgx.CollectRows(rows, pgx.RowTo[uuid.UUID])
	if err != nil {
		return err
	}
	var done []uuid.UUID
	for _, id := range ids {
		if err := s.Files.Remove(id); err != nil {
			slog.ErrorContext(ctx, "photo files", "err", err)
			continue
		}
		done = append(done, id)
	}
	_, err = s.DB.Exec(ctx, `DELETE FROM photo_trash WHERE id = ANY($1)`, done)
	return err
}

// SweepEvery runs Sweep until ctx ends.
func (s *Store) SweepEvery(ctx context.Context, every time.Duration) {
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		if err := s.Sweep(ctx); err != nil && ctx.Err() == nil {
			slog.ErrorContext(ctx, "photo sweep", "err", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}
