// Package snow serves the snow cover on the map: the Copernicus Land
// Monitoring Service's daily gap-filled fractional snow cover (60 m) as PNG
// tiles, made by the snow-cover job (infra/data-import).
package snow

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// The zooms the job makes tiles for; maps draw them larger beyond.
const (
	MinZoom = 6
	MaxZoom = 11
)

// Attribution is the wording the CLMS data policy asks for derived products.
const Attribution = "Generated using European Union's Copernicus Land Monitoring Service information"

// ErrNotFound is returned for a day that is not (or no longer) there.
var ErrNotFound = errors.New("snow cover not found")

// Class is where a colour of the tiles starts.
type Class struct {
	From  int    `json:"from" doc:"Snow cover in %"`
	Color string `json:"color" doc:"#rrggbb"`
}

// Legend is the tiles' colours; it must match snow-cover.py.
var Legend = []Class{{15, "#c6dbef"}, {50, "#6baed6"}, {90, "#2171b5"}}

// Extent is the tiles' area: Switzerland and Liechtenstein with 15 km
// around (infra/data-import/border.geojson).
type Extent struct {
	West  float64 `json:"west"`
	South float64 `json:"south"`
	East  float64 `json:"east"`
	North float64 `json:"north"`
}

// Area is the border file's extent.
var Area = Extent{West: 5.76, South: 45.68, East: 10.70, North: 47.95}

// Store reads the tiles.
type Store struct {
	DB *pgxpool.Pool
}

// Latest returns the newest day with snow cover; ok is false while there is
// none.
func (s *Store) Latest(ctx context.Context) (time.Time, bool, error) {
	var day *time.Time // NULL without any
	if err := s.DB.QueryRow(ctx, `SELECT max(day) FROM snow_days`).Scan(&day); err != nil {
		return time.Time{}, false, fmt.Errorf("snow: latest: %w", err)
	}
	if day == nil {
		return time.Time{}, false, nil
	}
	return *day, true, nil
}

// Tile returns a tile of day: nil where there is no snow, ErrNotFound for
// a day that is not there.
func (s *Store) Tile(ctx context.Context, day time.Time, z, x, y int) ([]byte, error) {
	var b []byte
	var known bool
	err := s.DB.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM snow_days WHERE day = $1),
		(SELECT png FROM snow_tiles WHERE day = $1 AND z = $2 AND x = $3 AND y = $4)`, day, z, x, y).Scan(&known, &b)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return nil, fmt.Errorf("snow: tile: %w", err)
	}
	if !known {
		return nil, ErrNotFound
	}
	return b, nil
}
