// Package testdb gives integration tests an isolated, migrated PostGIS
// database. One container is started per test binary; every call to New
// clones a fresh database from a migrated template, which takes milliseconds.
//
// The image defaults to alvyo-postgis:18 (built by `make infra-up`);
// override it with ALVYO_TEST_PG_IMAGE. Tests are skipped with -short.
package testdb

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/url"
	"os"
	"sync"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/testcontainers/testcontainers-go/modules/postgres"

	"github.com/tellbow/alvyo/api/internal/db"
)

const templateDB = "alvyo_template"

var (
	once     sync.Once
	baseURL  *url.URL
	startErr error
)

// New returns a pool connected to a new database with all migrations applied.
// The database is dropped when the test ends.
func New(t testing.TB) *pgxpool.Pool {
	t.Helper()
	if testing.Short() {
		t.Skip("integration test (needs Docker)")
	}
	once.Do(start)
	if startErr != nil {
		t.Fatalf("testdb: %v", startErr)
	}

	ctx := context.Background()
	name := "test_" + randomHex(8)
	admin, err := pgx.Connect(ctx, urlFor("postgres"))
	if err != nil {
		t.Fatalf("testdb: %v", err)
	}
	defer func() { _ = admin.Close(ctx) }()
	if _, err := admin.Exec(ctx, fmt.Sprintf("CREATE DATABASE %s TEMPLATE %s", name, templateDB)); err != nil {
		t.Fatalf("testdb: %v", err)
	}

	pool, err := pgxpool.New(ctx, urlFor(name))
	if err != nil {
		t.Fatalf("testdb: %v", err)
	}
	t.Cleanup(func() {
		pool.Close()
		if c, err := pgx.Connect(ctx, urlFor("postgres")); err == nil {
			_, _ = c.Exec(ctx, fmt.Sprintf("DROP DATABASE %s WITH (FORCE)", name))
			_ = c.Close(ctx)
		}
	})
	return pool
}

func start() {
	ctx := context.Background()
	img := os.Getenv("ALVYO_TEST_PG_IMAGE")
	if img == "" {
		img = "alvyo-postgis:18"
	}
	// The container is removed by testcontainers' reaper when the test
	// binary exits.
	c, err := postgres.Run(ctx, img,
		postgres.WithDatabase(templateDB),
		postgres.WithUsername("alvyo"),
		postgres.WithPassword("alvyo"),
		postgres.BasicWaitStrategies(),
	)
	if err != nil {
		startErr = err
		return
	}
	raw, err := c.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		startErr = err
		return
	}
	if baseURL, err = url.Parse(raw); err != nil {
		startErr = err
		return
	}
	if _, err := db.Migrate(ctx, raw); err != nil {
		startErr = err
	}
}

func urlFor(database string) string {
	u := *baseURL
	u.Path = "/" + database
	return u.String()
}

func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
