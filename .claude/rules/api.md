---
paths:
  - "api/**"
  - "swiss/**"
---

# Go API and Swiss domain logic

- huma v2, code first: handlers in `api/internal/httpapi/`, one file per area,
  registered in `server.go`. The OpenAPI spec comes from the Go types; after
  changing them run `make api-client`.
- Access: `loadRoute`, `loadJourney`, `loadCollection` answer 404 for items the
  caller may not see; never reveal that a private item exists. Costly
  endpoints use `requireUser` and a limiter from `Limits` (`httpapi/auth.go`);
  work per item counts with `AllowN`.
- Errors: client mistakes are `huma.Error4xx` with a short English message.
  A plain Go error becomes a 500 that is logged; the client only sees
  "unexpected error occurred". Values the database would refuse (dates, ids)
  are checked in a `Resolve` method on the input type, so they give 422.
- Stores use pgx, one package per domain. A transaction that counts and then
  inserts locks the parent row first (see the `tx` helpers of journeys and
  collections).
- Migrations: `api/migrations/NNNN_name.sql` (goose, with a Down part).
  Queries for sqlc in `api/queries/`, then `make sqlc`.
- Tests: `testdb.New(t)` gives PostGIS with the real migrations
  (testcontainers). GraphHopper, geo.admin and OJP are `httptest` servers
  with recorded answers in `testdata/`. HTTP tests use the `client` helper in
  `httpapi/auth_test.go` (cookie jar, Origin header). Real services only in
  `//go:build live` tests.
- `swiss/` is domain logic without database. Hiking times match the official
  figures: a change there needs `go run ./swiss/cmd/calibrate` and the tables
  in `docs/hiking-time.md`.
