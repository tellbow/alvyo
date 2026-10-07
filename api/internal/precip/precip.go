// Package precip serves the rain on the map: pictures of MeteoSwiss's radar
// (the last hour, every 5 minutes) and of the ICON-CH1 forecast (the next
// hours), made by the weather-precip job (infra/data-import).
package precip

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Ahead bounds the forecast shown.
const Ahead = 12 * time.Hour

// ErrNotFound is returned for a picture that is not (or no longer) there.
var ErrNotFound = errors.New("picture not found")

// Level is where a colour of the pictures starts.
type Level struct {
	From  float64 `json:"from" doc:"Rain in mm/h"`
	Color string  `json:"color" doc:"#rrggbb"`
}

// Legend is the pictures' colours; it must match weather-precip.py.
var Legend = []Level{
	{0.1, "#a6dbf7"}, {0.5, "#5faaf0"}, {1, "#286ee6"}, {2, "#143cc8"}, {4, "#3c14aa"},
	{7, "#8c28c8"}, {10, "#e68c1e"}, {20, "#dc1e1e"}, {40, "#96005a"},
}

// Bounds are a picture's edges (it is in Web Mercator).
type Bounds struct {
	West  float64 `json:"west"`
	South float64 `json:"south"`
	East  float64 `json:"east"`
	North float64 `json:"north"`
}

// Frame is one picture of the timeline.
type Frame struct {
	Kind    string    `json:"kind" enum:"radar,forecast" doc:"radar measured, forecast from the model"`
	Time    time.Time `json:"time" doc:"radar: when measured; forecast: the end of the hour it shows"`
	Version int64     `json:"-"`
}

// Store reads the pictures.
type Store struct {
	DB *pgxpool.Pool
}

// Timeline returns the radar pictures and, after the newest, the forecast
// up to Ahead from now, oldest first, with the pictures' bounds.
func (s *Store) Timeline(ctx context.Context, now time.Time) ([]Frame, Bounds, error) {
	rows, err := s.DB.Query(ctx, `
		WITH newest AS (SELECT coalesce(max(valid_at), '-infinity') AS t FROM precip_frames WHERE kind = 'radar')
		SELECT kind, valid_at, extract(epoch FROM created_at)::bigint, west, south, east, north
		FROM precip_frames, newest
		WHERE kind = 'radar' OR (valid_at > newest.t AND valid_at > $1 AND valid_at <= $2)
		ORDER BY valid_at, kind DESC`, now, now.Add(Ahead))
	if err != nil {
		return nil, Bounds{}, fmt.Errorf("precip: timeline: %w", err)
	}
	var b Bounds
	frames, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (Frame, error) {
		var f Frame
		err := r.Scan(&f.Kind, &f.Time, &f.Version, &b.West, &b.South, &b.East, &b.North)
		return f, err
	})
	return frames, b, err
}

// PNG returns a picture.
func (s *Store) PNG(ctx context.Context, kind string, t time.Time) ([]byte, error) {
	var b []byte
	err := s.DB.QueryRow(ctx, `SELECT png FROM precip_frames WHERE kind = $1 AND valid_at = $2`, kind, t).Scan(&b)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return b, err
}
