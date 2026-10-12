# Alvyo

Swiss hiking platform replacing Komoot: Go API (`api/`, `swiss/`), SvelteKit
web app (`web/`), Flutter iOS app (`app/`). Plan, status and open
requirements: `docs/plan.md` — read it before planning work, and update it in
the same commit when a requirement is done or changes. Layout: `README.md`.

## How we work

- Commits go straight to `main`, no pull requests. Commit and push only when
  asked. A `v*` tag is a release (see the `release` skill); confirm first.
- Before a commit: formatting, lint and the tests of what changed (commands
  below); CI runs the same (`.github/workflows/ci.yml`).
- A bug fix comes with a test that fails without it.
- Every text users see exists in German, English, French and Italian:
  `web/messages/*.json` (Paraglide), `app/lib/l10n/app_*.arb` (then
  `flutter gen-l10n`). German is the reference; the UI says «du».
- After changing API types or operations: `make api-client` (CI fails on a
  stale `web/src/lib/api/openapi.json`). After SQL or migrations: `make sqlc`.
- What only a phone or a real hike can show goes into
  `docs/manual-tests.md`.
- Write like the surrounding code: short comments that say why, plain names.

## Commands

| What | Command |
|---|---|
| Dev stack (PostGIS, GraphHopper, tile cache, Mailpit) | `make infra-up`; GraphHopper needs ~2 min to load |
| API | `export ALVYO_DATABASE_URL='postgres://alvyo:alvyo@localhost:5432/alvyo?sslmode=disable'`, then `go run ./api/cmd/alvyo migrate && go run ./api/cmd/alvyo serve` |
| Web | `cd web && bun run dev` (http://localhost:5173) |
| Go tests | `go test ./swiss/... ./api/...` (testcontainers; needs Docker) |
| Go lint | `make lint-go` (golangci-lint in `api/` and `swiss/`) |
| Web checks | `cd web && bun run check && bun run lint && bunx vitest run` |
| Web end-to-end | `cd web && bunx playwright test` (starts its own API and web; needs the dev stack; local only, before every release: `.claude/rules/e2e.md`) |
| App | `cd app && dart format --output=none --set-exit-if-changed lib test integration_test && flutter analyze && flutter test` |
| App on the simulator / iPhone / Android emulator | the `app-simulator-tests` and `iphone-install` skills; Android: `app/README.md` |
| Supply chain (CI runs them too) | govulncheck, osv-scanner, zizmor, gitleaks: `docs/development.md`, «Supply chain» |

Live tests against GraphHopper and geo.admin: `go test -tags live
./swiss/elevation/ ./api/internal/routing/`. Locally, run Go tests without
`TESTCONTAINERS_RYUK_DISABLED` (CI sets it): with Ryuk off, every test
database container stays behind.

## Never

- Read or print secrets: `infra/.env.local-test` (holds the OJP key; source
  it only in a subshell), `cluster/alvyo/secret.yaml` in the gitops repo.
- Use another kubeconfig than `KUBECONFIG=~/.kube/k3s.yaml` with
  `--context rk1`; the default one holds unrelated clusters.
- Set image tags in the gitops repo by hand: Flux image automation does.
