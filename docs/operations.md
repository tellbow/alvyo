# Operations

## Server

One VPS in Switzerland or the EU is enough to start:

| | Minimum | Why |
|---|---|---|
| CPU | 4 vCPU | GraphHopper import (weekly), API |
| RAM | 8 GB | GraphHopper serves with ~3 GB heap, imports need ~4 GB more |
| Disk | 40 GB | OSM extract 0.6 GB, graph 2 GB (+2 GB during refresh), trail data 0.6 GB, tile cache up to 60 GB (`infra/tilecache/nginx.conf`, `max_size`) — size the cache to the disk; photos about 0.5 MB each (at most 1000 per person), plus 3 copies in the backups |

Docker with the Compose plugin, ports 80/443 open, a DNS record for the domain.

### Outbound connections

The API calls these services; allow them if egress is restricted:

| Host | For |
|---|---|
| `api3.geo.admin.ch` | Elevation profiles (every planned leg and every import) |
| `api.opentransportdata.swiss` | Connections (OJP), only if `ODYSGEH_OJP_TOKEN` is set |
| `api.komoot.de` | Komoot import. This is Komoot's unofficial API: when Komoot changes it, the import fails with 502, while GPX, KML, TCX and FIT upload keep working. |

Reverse proxies in front of `/api` must accept request bodies of 22 MB
(file imports: 20 MB plus form overhead).

### Sign-in providers (optional)

Besides passwords and passkeys, people can log in through OpenID Connect
providers you configure, e.g. Google:

1. Google Cloud console → APIs & Services → Credentials → OAuth client ID
   (web application), redirect URI
   `https://<DOMAIN>/api/v1/auth/oidc/google/callback`.
2. In `infra/.env`: `OIDC_PROVIDERS=google`, `OIDC_GOOGLE_CLIENT_ID=…`,
   `OIDC_GOOGLE_CLIENT_SECRET=…` (compose.prod.yaml passes them on).

Other providers (Microsoft, an own Keycloak or Authentik …) work the same with
their issuer URL; add their variables to `compose.prod.yaml` like Google's.
A provider login with the e-mail of an existing account does not enter that
account: its owner connects the provider on the account page first.

## First deployment

```sh
git clone https://github.com/tellbow/odysgeh.git /srv/odysgeh
cd /srv/odysgeh
make osm-fetch                          # OSM extracts for Switzerland + Liechtenstein
cp infra/.env.example infra/.env        # fill in DOMAIN, POSTGRES_PASSWORD, SMTP, CONTACT_EMAIL
cd infra
docker compose -f compose.prod.yaml up -d --build   # first start: GraphHopper imports ~2 min
docker compose -f compose.prod.yaml run --rm tlm-import   # official trail network, once a year
docker compose -f compose.prod.yaml run --rm places-import   # stops, huts, accommodation
```

Caddy obtains the TLS certificate on the first request to `https://$DOMAIN`.
Set `VERSION` in `.env` to the deployed git SHA (`git rev-parse --short HEAD`);
the About page shows it next to the source link (AGPL §13).

Before going public, e-mail swisstopo (geodata@swisstopo.ch) about the
expected tile volume: the WMTS terms allow restricting "excessive use".

## Scheduled jobs (cron, as the deploy user)

```cron
15 2 * * *  /srv/odysgeh/infra/ops/backup.sh           # nightly pg_dump (14 days kept) and photos tar (3 kept)
0  4 * * 1  /srv/odysgeh/infra/ops/refresh-graph.sh    # weekly OSM refresh, graph swap, places
0  5 1 * *  /srv/odysgeh/infra/ops/restore-check.sh    # monthly restore test
```

Copy `infra/backups/` off the machine as well (e.g. `rclone sync` to object
storage). The scripts read `infra/.env` through Docker Compose.

Photos live in the `photos` volume (`/data/photos` in the api container). To
restore them with the database dump of the same night:
`docker compose -f compose.prod.yaml cp - api:/data < backups/photos-<stamp>.tar`
(the tar holds the `photos` directory). Files of deleted photos are removed
by the API within a minute.

## Updates

```sh
cd /srv/odysgeh && git pull
cd infra && docker compose -f compose.prod.yaml up -d --build
```

Migrations run automatically (`migrate` service) before the API starts. Take a
backup first when the release notes mention migrations.

## Releases (container images)

Pushing a version tag builds all images for amd64 and arm64 and publishes them
to GHCR (`.github/workflows/release.yml`):

```sh
git tag v0.1.0 && git push origin v0.1.0
# → ghcr.io/tellbow/odysgeh-{api,web,postgis,graphhopper,data-import}:0.1.0
```

New GHCR packages are private; make them public once in the package settings
(or give the cluster a pull secret). The data-import image carries its
scripts, so Kubernetes jobs can run `sh /scripts/import-places.sh` etc.

## Moderation

```sh
cd /srv/odysgeh/infra
docker compose -f compose.prod.yaml exec api /odysgeh user ban <username>     # ends sessions, makes routes, journeys and collections private
docker compose -f compose.prod.yaml exec api /odysgeh user unban <username>
docker compose -f compose.prod.yaml exec api /odysgeh user role <username> moderator   # sees "Moderation" in the app
docker compose -f compose.prod.yaml exec api /odysgeh route unpublish <route-id>
```

## Verified locally (2026-09-22)

The production stack ran on `DOMAIN=localhost` (Caddy's internal CA): pages,
API, tiles and security headers through Caddy; signup with mail delivery; the
cross-origin check; `Secure; HttpOnly; SameSite=Lax` session cookie; routing;
`backup.sh` + `restore-check.sh`; `refresh-graph.sh` (import 2 min, swap,
routing works again within seconds); `user ban` blocking login.
