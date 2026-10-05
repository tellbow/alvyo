# Alvyo

Plan, share and walk hikes in Switzerland — custom routes on the swisstopo national map,
official Swiss hiking times, SAC difficulty, and multi-week stage journeys.

Status: early development. Working: accounts, route planning on the swisstopo
map (Swiss hiking time, SAC grade, elevation profile, breakdowns), saving and
editing routes, multi-week stage journeys (stops, huts, public transport
connections), sharing by link and by invitation, collections, tags, GPX export,
import from GPX, KML, TCX, FIT and Komoot, discovery of public hikes on the
map, how far one gets in 2, 4 and 8 hours from a point (isochrones timed by
slope), public or private profiles, friends (search, requests, invite links),
hiked marks on routes and journeys, likes, comments, following with a news
feed, OpenTelemetry traces and metrics, reports
and a moderation queue, photos (metadata removed, pinned along the route),
passkeys and sign-in with OpenID Connect providers, German, English, French
and Italian, link previews. Hiking times match the official SchweizMobil
figures ([docs/hiking-time.md](docs/hiking-time.md)). The iOS app shows
routes on the national map, saves them offline, navigates with spoken turns,
records hikes and imports Apple Watch workouts ([app/README.md](app/README.md)).
Plan, status and what comes next: [docs/plan.md](docs/plan.md). Deployment:
[docs/operations.md](docs/operations.md).

## Layout

| Path     | What                                                                 |
|----------|----------------------------------------------------------------------|
| `swiss/` | Go module: Swiss domain logic (hiking time, SAC, LV95, elevation, OJP) |
| `api/`   | Go module: HTTP API (`alvyo` binary)                                |
| `web/`   | SvelteKit web app                                                     |
| `app/`   | Flutter app (iOS)                                                     |
| `infra/` | Docker Compose, GraphHopper, tile cache, data import                  |
| `docs/`  | Plan, ADRs, hiking-time calibration, development and operations       |

## Development

Needs Go 1.26, bun and Docker. Setup, daily workflow, tests and a
production-like local run: [docs/development.md](docs/development.md).

```sh
make osm-fetch && make infra-up          # once: map data + containers
export ALVYO_DATABASE_URL='postgres://odysgeh:odysgeh@localhost:5432/odysgeh?sslmode=disable'
go run ./api/cmd/alvyo migrate && go run ./api/cmd/alvyo serve
cd web && bun run dev                    # → http://localhost:5173
```

## License

AGPL-3.0-only — see [LICENSE](LICENSE). Third-party data and code attributions: [NOTICE](NOTICE).
