package official

import (
	"context"
	"errors"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Info marks a route or journey as an official Wanderland route; the
// clients link it to SchweizMobil and name the source.
type Info struct {
	Number string `json:"number" doc:"The route's number at SchweizMobil (schweizmobil.ch/de/wanderland/route-{number})"`
	Kind   string `json:"kind" enum:"national,regional,local,handicap"`
}

// ForRoute is the Info of a route, or of the journey it is a stage of; nil
// for others.
func ForRoute(ctx context.Context, db *pgxpool.Pool, id uuid.UUID) (*Info, error) {
	var in Info
	err := db.QueryRow(ctx, `
		SELECT o.nr, o.kind FROM routes r JOIN official o ON o.route_id = r.id OR o.journey_id = r.journey_id
		WHERE r.id = $1`, id).Scan(&in.Number, &in.Kind)
	return info(in, err)
}

// ForJourney is the Info of a journey; nil for others.
func ForJourney(ctx context.Context, db *pgxpool.Pool, id uuid.UUID) (*Info, error) {
	var in Info
	err := db.QueryRow(ctx, `SELECT nr, kind FROM official WHERE journey_id = $1`, id).Scan(&in.Number, &in.Kind)
	return info(in, err)
}

func info(in Info, err error) (*Info, error) {
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &in, nil
}
