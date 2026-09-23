// Package db opens the PostgreSQL connection pool and applies migrations.
package db

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
	_ "github.com/jackc/pgx/v5/stdlib" // database/sql driver for goose
	"github.com/pressly/goose/v3"

	"github.com/tellbow/odysgeh/api/migrations"
)

// Open connects to the database and checks the connection.
func Open(ctx context.Context, url string) (*pgxpool.Pool, error) {
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		return nil, fmt.Errorf("db: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("db: %w", err)
	}
	return pool, nil
}

// Migrate applies all pending migrations and returns how many ran.
func Migrate(ctx context.Context, url string) (int, error) {
	sqlDB, err := sql.Open("pgx", url)
	if err != nil {
		return 0, fmt.Errorf("migrate: %w", err)
	}
	defer func() { _ = sqlDB.Close() }()

	p, err := goose.NewProvider(goose.DialectPostgres, sqlDB, migrations.FS)
	if err != nil {
		return 0, fmt.Errorf("migrate: %w", err)
	}
	res, err := p.Up(ctx)
	if err != nil {
		return 0, fmt.Errorf("migrate: %w", err)
	}
	return len(res), nil
}
