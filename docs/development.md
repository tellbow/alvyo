# Development

Needs Go 1.26 (`go.mod` pins the toolchain, 1.26.6, which Go downloads by
itself), [bun](https://bun.sh) and Docker. All commands run from the
repository root unless noted.

## First setup (once per machine)

```sh
make osm-fetch      # OSM extracts: CH, LI and 15 km beyond (~4 GB download) → infra/data/osm
make infra-up       # PostGIS, GraphHopper, tile cache, Mailpit (docker compose),
                    # their ports on 127.0.0.1 only
                    # GraphHopper builds its routing graph on first start (~2 min)
# the database is still called odysgeh, from before the rename (operations.md)
export ALVYO_DATABASE_URL='postgres://odysgeh:odysgeh@localhost:5432/odysgeh?sslmode=disable'
go run ./api/cmd/alvyo migrate
make tlm-import     # official hiking trails into PostGIS (~200 MB download), needed for SAC grades
make places-import  # stops (BAV) and huts/accommodation (OSM) for stage start and end (~5 s)
cd web && bun install
```

## Daily work

Containers still running? `make infra-up` is harmless if they are. Then, in two
terminals:

```sh
# terminal 1 — API on :8080
export ALVYO_DATABASE_URL='postgres://odysgeh:odysgeh@localhost:5432/odysgeh?sslmode=disable'
go run ./api/cmd/alvyo migrate     # after pulling new migrations
go run ./api/cmd/alvyo serve

# terminal 2 — web app on :5173
cd web && bun run dev
```

Open http://localhost:5173. The Vite dev server forwards `/api` to the API and
`/tiles` to the tile cache, so everything runs on one origin.

| Service     | URL |
|-------------|-----|
| Web app     | http://localhost:5173 |
| API         | http://localhost:8080/api/v1 — OpenAPI docs at `/api/v1/docs` |
| Mailpit     | http://localhost:8025 — verification and reset e-mails land here |
| GraphHopper | http://localhost:8989 |
| Tile cache  | http://localhost:8081/tiles/wmts/{layer}/{z}/{x}/{y}.{ext} |

Planning works without confirming the e-mail address; sharing (by link or
publicly) needs it — use the link from Mailpit.

`make infra-down` stops the containers (data volumes stay).

### API configuration

Environment variables of `alvyo serve` (defaults match the dev stack):

| Variable | Default |
|---|---|
| `ALVYO_DATABASE_URL` | required |
| `ALVYO_LISTEN` | `:8080` |
| `ALVYO_PUBLIC_URL` | `http://localhost:5173` — origin of the web app; POSTs from other origins get 403 |
| `ALVYO_GRAPHHOPPER_URL` | `http://localhost:8989` |
| `ALVYO_TILES_URL` | `http://localhost:8081` |
| `ALVYO_CACHE_DIR` | `$TMPDIR/alvyo` (rendered preview images) |
| `ALVYO_PHOTOS_DIR` | `data/photos`, relative to where the API runs (uploaded photos; git-ignored) |
| `ALVYO_SMTP_HOST` / `_PORT` / `_USER` / `_PASSWORD` / `_TLS` | Mailpit: `localhost` / `1025` / – / – / `none` |
| `ALVYO_MAIL_FROM` | `Alvyo <noreply@localhost>` |
| `ALVYO_LOG_LEVEL` | `info` (`debug` logs every request) |
| `ALVYO_OJP_TOKEN` | unset — opentransportdata.swiss API key for public transport connections; without it the search answers 503 and the UI shows only SBB links |
| `ALVYO_OJP_URL` | `https://api.opentransportdata.swiss/ojp20` |
| `ALVYO_OIDC_PROVIDERS` | unset — comma-separated ids of OpenID Connect sign-in providers, e.g. `google`; each needs `ALVYO_OIDC_<ID>_ISSUER`, `_CLIENT_ID`, `_CLIENT_SECRET` and optionally `_NAME` (button label). Register `<ALVYO_PUBLIC_URL>/api/v1/auth/oidc/<id>/callback` as redirect URI at the provider. Playwright runs a fake provider (`web/tests/e2e/fake-idp.mjs`) |
| `ALVYO_RELAXED_LIMITS` | unset — `true` lifts the per-IP signup limit (5 per 10 min); Playwright sets it, never use it in production |

The web app reads `API_INTERNAL_URL` (default `http://localhost:8080`) for
server-side rendering and the Vite proxy.

## Code generation

```sh
make sqlc           # after changing api/queries/*.sql or migrations
make api-client     # after changing API types: regenerates web/src/lib/api/{openapi.json,schema.d.ts}
```

## Tests

```sh
make test                    # Go unit + integration tests (need Docker), web unit tests
make lint                    # golangci-lint, prettier, eslint
make check                   # svelte-check (types)
cd web && bun run test:e2e   # Playwright against the dev stack
```

The end-to-end tests start their own API (:18080) and a production build of
the web app (:4173); only the containers must be running. They fail on any
uncaught browser error or console error (`tests/e2e/fixtures.ts`).

Accounts in tests: signing up does not log in, the e-mailed link does
(operations.md, «Accounts»). Go tests sign up with `s.signup(c, email,
username)` (`api/internal/httpapi/auth_test.go`): it confirms through the
link and then marks the address unconfirmed again, so a test sets what it
checks. Playwright tests use `signUp(page.request, { data })` from
`tests/e2e/accounts.ts`, which confirms through Mailpit.

Live tests against the real external services:
`go test -tags live ./swiss/elevation/ ./api/internal/routing/`, and with
`ALVYO_OJP_TOKEN` set `go test -tags live ./swiss/ojp/` (one planner
request). The e2e tests stub the planner, so they never use the OJP quota.

## Supply chain

CI (`.github/workflows/ci.yml`, also every Monday) checks more than the
tests; the same locally:

```sh
(cd api && go run golang.org/x/vuln/cmd/govulncheck@v1.1.4 ./...)   # and in swiss/
go run github.com/google/osv-scanner/v2/cmd/osv-scanner@v2.6.0 scan source -L web/bun.lock -L app/pubspec.lock
uvx zizmor .github/workflows                                          # workflow risks
uvx semgrep scan --config p/default --metrics=off                     # static analysis; the rules CI leaves out and why: ci.yml
docker run --rm -v "$PWD:/repo" ghcr.io/gitleaks/gitleaks:v8.30.0 git /repo --redact -c /repo/.gitleaks.toml
```

Actions are pinned to commit SHAs. Renovate (`renovate.json`) opens grouped
pull requests on Mondays for Go, web, app, images and actions, for releases
at least 7 days old; patches and digests merge themselves once CI passes.
`web/package.json` overrides `cookie` and `source-map-js` for fixes their
dependents do not take up yet; drop an override once they do.
Vulnerabilities are reported privately ([SECURITY.md](../SECURITY.md)).
`make scorecard` runs the OpenSSF Scorecard as a checklist (2026-10-08:
5.8; low where a private solo project cannot score: reviews, branch
protection, fuzzing, its age).

## Production-like, locally

Caddy on https://localhost with its internal certificate (the browser warns).
Stop the dev GraphHopper first — both would use the same graph folder:

```sh
docker compose -f infra/compose.yaml stop graphhopper
cd infra
docker compose -f compose.prod.yaml --env-file .env.local-test up -d --build
# … then tear down:
docker compose -f compose.prod.yaml --env-file .env.local-test down -v
docker compose -f compose.yaml start graphhopper
```

`infra/.env.local-test` is not committed; copy `infra/.env.example` and set
`DOMAIN=localhost`, `SMTP_HOST=host.docker.internal`, `SMTP_PORT=1025`,
`SMTP_TLS=none`. Real deployments: [operations.md](operations.md).

## Troubleshooting

- **"Port 5173 is in use, trying another one"** — another dev server is running;
  Vite then picks 5174, but the API only accepts the origin in
  `ALVYO_PUBLIC_URL`, so logins fail with 403. Stop the other one.
- **The page reloads right after starting** — Vite re-optimizes dependencies
  after config or dependency changes and reloads once. Wait a moment.
- **No routes, "Kein Weg in der Nähe"** — GraphHopper is still importing
  (`docker compose -f infra/compose.yaml logs -f graphhopper`).
- **SAC grade always "not an official trail"** — `make tlm-import` not run.
- **Stages show no start or end place, the picker finds nothing** — `make places-import`
  not run (the journeys end-to-end test needs it too).
