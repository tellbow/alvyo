# Alvyo

Plan, share and walk hikes in Switzerland — custom routes on the swisstopo national map,
official Swiss hiking times, SAC difficulty, and multi-week stage journeys.

Status: early development. What works, in short (details, status and what
comes next: [docs/plan.md](docs/plan.md); deployment: [docs/operations.md](docs/operations.md), restoring it: [docs/restore.md](docs/restore.md)):

- **Planning:** routes on the swisstopo map with Swiss hiking time ([matching SchweizMobil](docs/hiking-time.md)), SAC grade, elevation profile, weather, closures and how far one gets in 2, 4 and 8 hours.
- **Journeys:** multi-week stage journeys planned from start, destination and days, with huts for the nights and public transport.
- **Sharing and community:** public, by link or invitation; collections, a discovery map, friends, a feed, likes, comments and photos.
- **App:** iOS, with the national map offline, spoken navigation, recording, an Apple Watch app and the Watch's hikes imported ([app/README.md](app/README.md)).
- **AI assistants and the command line:** an MCP server and `alvyo-cli` with a personal access token, read-only ([docs/mcp.md](docs/mcp.md)).
- **Data and privacy:** GPX export, import from GPX, KML, TCX and FIT, privacy zones; in German, English, French and Italian.

## Screenshots

<table>
<tr>
<td><img src="docs/images/planner.webp" alt="Planner with a route and its elevation profile"><br>Planning a route</td>
<td><img src="docs/images/route.webp" alt="A route's page with its numbers, weather and trail conditions"><br>A route's page</td>
</tr>
<tr>
<td><img src="docs/images/journey.webp" alt="A journey with two stages"><br>A journey and its stages</td>
<td><img src="docs/images/reach.webp" alt="Areas reached within 2, 4 and 8 hours from Kandersteg"><br>How far one gets («Reichweite»)</td>
</tr>
<tr>
<td><img src="docs/images/discover.webp" alt="The discovery map of public hikes"><br>Discovering public hikes</td>
<td align="center"><img src="docs/images/app-route.webp" width="32%" alt="A route in the iOS app"> <img src="docs/images/app-nav.webp" width="32%" alt="Navigation in the iOS app"><br>The app: a route, navigating</td>
</tr>
</table>

## Layout

| Path     | What                                                                 |
|----------|----------------------------------------------------------------------|
| `swiss/` | Go module: Swiss domain logic (hiking time, SAC, LV95, elevation, OJP) |
| `api/`   | Go module: HTTP API (`alvyo` binary)                                |
| `web/`   | SvelteKit web app                                                     |
| `app/`   | Flutter app (iOS)                                                     |
| `infra/` | Docker Compose, GraphHopper, tile cache, data import                  |
| `docs/`  | Plan, ADRs, hiking-time calibration, development and operations       |

How the parts fit together: [docs/architecture.md](docs/architecture.md).

## Development

Needs Go 1.26, bun and Docker. Setup, daily workflow, tests and a
production-like local run: [docs/development.md](docs/development.md).

```sh
make osm-fetch && make infra-up          # once: map data + containers
export ALVYO_DATABASE_URL='postgres://alvyo:alvyo@localhost:5432/alvyo?sslmode=disable'
go run ./api/cmd/alvyo migrate && go run ./api/cmd/alvyo serve
cd web && bun run dev                    # → http://localhost:5173
```

## License

AGPL-3.0-only — see [LICENSE](LICENSE). Third-party data and code attributions: [NOTICE](NOTICE).
Terms of every data source and where each is credited: [docs/licensing.md](docs/licensing.md).
Contributions: [CONTRIBUTING.md](CONTRIBUTING.md) (with a [CLA](CLA.md)).
