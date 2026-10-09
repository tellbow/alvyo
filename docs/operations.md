# Operations

Alvyo was called odysgeh before 0.8.0. The database, its user and the
cluster's secret kept that name; the Kubernetes namespace is alvyo since
2026-09-27 (the volumes moved along).

## Server

One VPS in Switzerland or the EU is enough to start:

| | Minimum | Why |
|---|---|---|
| CPU | 4 vCPU | GraphHopper import (weekly), API |
| RAM | 8 GB | GraphHopper serves with ~3 GB heap, imports need ~4 GB more |
| Disk | 40 GB | OSM extract 0.6 GB, graph 2 GB (+2 GB during refresh), trail data 0.6 GB, tile cache up to 60 GB (`infra/tilecache/nginx.conf`, `max_size`) — size the cache to the disk; photos about 0.5 MB each (at most 1000 per person), plus 3 copies in the backups; offline map packs at most 512 MiB in the API cache (ADR-0004) |

Docker with the Compose plugin, ports 80/443 open, a DNS record for the domain.

### Outbound connections

The API calls these services; allow them if egress is restricted:

| Host | For |
|---|---|
| `api3.geo.admin.ch` | Elevation profiles (every planned leg and every import), place search in the planner |
| `api.opentransportdata.swiss` | Connections (OJP), only if `ALVYO_OJP_TOKEN` is set |
| `api.github.com` | Bug reports («Fehler melden») as issues, only if `ALVYO_GITHUB_TOKEN` is set: a fine-grained token for `tellbow/alvyo` (`ALVYO_GITHUB_REPO` for another) with «Issues: read and write». Without it reports are only kept in the database. |
| `api.komoot.de` | Komoot import. This is Komoot's unofficial API: when Komoot changes it, the import fails with 502, while GPX, KML, TCX and FIT upload keep working. |

The tile cache fetches from `wmts.geo.admin.ch` and `tiles.mapterhorn.com`
and checks their certificates (`proxy_ssl_verify`; the cluster has its own
copy of the configuration in the gitops repo, `cluster/alvyo/tilecache-nginx.conf`).

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
   On the cluster: `ALVYO_OIDC_GOOGLE_CLIENT_ID` and
   `ALVYO_OIDC_GOOGLE_CLIENT_SECRET` in `odysgeh-secret` (`sops
   cluster/alvyo/secret.yaml` in the gitops repo), the provider list, name
   and issuer in `configmap.yaml`. A provider listed without its secret
   stops the API from starting: the keys go in first.
3. Check: `GET /api/v1/auth/providers` lists it, the login page shows
   «Mit Google anmelden».

Other providers (Microsoft, an own Keycloak or Authentik …) work the same with
their issuer URL; add their variables to `compose.prod.yaml` like Google's.
A provider login with the e-mail of an existing account does not enter that
account: its owner connects the provider on the account page first.

### Accounts

Signing up needs working e-mail (SMTP): an account logs in only once its
address is confirmed.

- Signing up answers the same for every address, so that it does not show
  who has an account; an address with one gets an e-mail how to log in
  instead (or a new link while it is not confirmed). Only a taken username
  is refused.
- The link names the account («Konto «x» bestätigen?») and logs in on the
  button. Logging in with an unconfirmed address sends a new link.
  Accounts from before 2026-10-08 that never confirmed are asked to on
  their next login; their sessions keep working until then.
- A password reset ends all sessions and removes passkeys and provider
  sign-ins: whoever resets takes the account over, also from someone who
  signed up with another person's address.
- A session ends after 30 days without use and 180 days after the login at
  the latest. «Auf allen anderen Geräten abmelden» (account page, the app's
  profile) ends all others.

## First deployment

```sh
git clone https://github.com/tellbow/alvyo.git /srv/alvyo
cd /srv/alvyo
make osm-fetch                          # OSM extracts: Switzerland, Liechtenstein, 15 km beyond
cp infra/.env.example infra/.env        # fill in DOMAIN, POSTGRES_PASSWORD, SMTP, CONTACT_EMAIL
cd infra
docker compose -f compose.prod.yaml up -d --build   # first start: GraphHopper imports ~2 min
docker compose -f compose.prod.yaml run --rm tlm-import   # official trail network, once a year
docker compose -f compose.prod.yaml run --rm places-import   # stops, huts, accommodation
docker compose -f compose.prod.yaml run --rm wanderland-import   # the official routes
```

Caddy obtains the TLS certificate on the first request to `https://$DOMAIN`.
Set `VERSION` in `.env` to the deployed git SHA (`git rev-parse --short HEAD`);
the About page shows it next to the source link (AGPL §13).

Before going public, e-mail swisstopo (geodata@swisstopo.ch) about the
expected tile volume: the WMTS terms allow restricting "excessive use".

## Scheduled jobs (cron, as the deploy user)

```cron
15 2 * * *  /srv/alvyo/infra/ops/backup.sh           # nightly pg_dump (14 days kept) and photos tar (3 kept)
0  4 * * 1  /srv/alvyo/infra/ops/refresh-graph.sh    # weekly OSM refresh, graph swap, places
0  5 1 * *  /srv/alvyo/infra/ops/restore-check.sh    # monthly restore test
0  4 3 * *  cd /srv/alvyo/infra && docker compose -f compose.prod.yaml run --rm wanderland-import   # official routes
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
cd /srv/alvyo && git pull
cd infra && docker compose -f compose.prod.yaml up -d --build
```

Migrations run automatically (`migrate` service) before the API starts. Take a
backup first when the release notes mention migrations.

Since 2026-10-08 the GraphHopper and data-import images run as uid 1000,
not root: on a server that ran them before, hand their data over once
before the update, `sudo chown -R 1000:1000 infra/data`.

### Hardening (Kubernetes)

Every pod in the cluster runs as a fixed uid that is not root (API 65532,
web 1000, PostgreSQL and its backup 999, tile cache and redirect 101 as
nginx, GraphHopper and the data-import jobs 1000), with no Linux
capabilities, no privilege escalation, seccomp `RuntimeDefault` and a
read-only root filesystem; what they write besides their volumes goes to
an emptyDir (`/tmp`, PostgreSQL's socket directory). Only `graph-refresh`
gets a service account token (it restarts GraphHopper). The `geodata`
volume belongs to uid 1000; Longhorn does not apply `fsGroup` to
ReadWriteMany volumes, so a pod writing to it must run as 1000. The nginx
configurations keep their pid file and temp files in `/tmp`.

## Releases (container images)

Write the version's row of the release table in [plan.md](plan.md) first
(the «next» row gets the number and date) and its line for «Was ist neu» on
the About page (`web/src/lib/news/releases.ts`, four languages), commit,
then tag that commit, signed (the `release` skill has all steps). The
workflow (`.github/workflows/release.yml`) refuses a tag not signed with
the key in `.github/release-signers.asc`; it builds all images for amd64
and arm64, each with an SBOM and its provenance, signs them with cosign
(keyless: the workflow's identity, entered in Sigstore's public
transparency log), publishes them to GHCR and creates a GitHub Release
whose notes are that row:

```sh
git tag -s v0.1.0 -m "Alvyo 0.1.0: …" && git push origin v0.1.0
# → ghcr.io/tellbow/alvyo-{api,web,postgis,graphhopper,data-import}:0.1.0
docker buildx imagetools inspect ghcr.io/tellbow/alvyo-api:0.1.0 --format '{{json .SBOM}}'   # what is in it
cosign verify ghcr.io/tellbow/alvyo-api:0.1.0 \
  --certificate-identity-regexp '^https://github.com/tellbow/alvyo/.github/workflows/release.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com   # built by this repository's release
```

Another person releasing adds their public key to `.github/release-signers.asc`.

Releases are immutable (repository setting): a release and its tag cannot
be changed afterwards; a mistake is fixed with the next patch version.

A change of `infra/graphhopper/config.yml` or its custom models needs a new
graph: GraphHopper does not start on a graph built with other profiles. Run
the graph refresh (or empty the graph cache) right after the new
`alvyo-graphhopper` image is deployed.

The graph has elevation for the slopes of the isochrones' time profiles
(requirement 65): on import GraphHopper downloads the 30 m terrain tiles of
AWS Terrain Tiles (skadi) into `/data/elevation-cache` (about 210 MB, kept
for later imports). With them the graph is 0.67 GB instead of 0.61 GB and
the import needs about 2.9 GB of heap (local, 2026-10-05: 8 min reading the
OSM data, 1 min per CH profile; on rk1 11 min with a 4 GB heap, 4.7 GiB of
memory). Routes are found as before; the turns of
map matching are as many as before on GPS tracks (54 against 55 on 20
noisy tracks).

The OSM data reaches 15 km beyond the border (requirement 31): `fetch-and-merge.sh`
downloads about 3.4 GB of neighbouring extracts (kept, so later runs download
only what changed) and cuts them with `osmium extract`, which needs up to
3.7 GiB of memory; with them the data volume holds about 4.5 GB of OSM files
and 0.6 GB per graph (three during a refresh). The graph import stays within
a 3 GB heap (2.3 GB used, 3 min); GraphHopper serves it in about 1.4 GB
(the old graph: 0.7 GB), well within its 4.5 GiB limit.

New GHCR packages are private; make them public once in the package settings
(or give the cluster a pull secret). The data-import image carries its
scripts, so Kubernetes jobs can run `sh /scripts/import-places.sh` etc. The
cron jobs `places-import` and `tlm-import` are suspended: after a change to
their script, run them by hand (`kubectl create job --from=cronjob/places-import …`);
0.16.0's points of interest were missing until then. On a new cluster run
both once: the official trail network (`tlm-import`) was missing on this one
until 2026-10-02, so routes planned before showed all their way as «Kein
Wanderweg» with a guessed SAC grade. After loading or updating the network,
`alvyo route retrail` (in the api container: `kubectl exec deploy/api --
/alvyo route retrail`) matches every stored route against it again and grades
it anew; line, times and version stay. Running it again changes nothing.

## Official routes

The routes of Wanderland Schweiz (ASTRA and SchweizMobil) are public routes
and journeys of the account `wanderland`, made by the API from what
`wanderland-import` loaded (on the cluster a CronJob on the 3rd of each
month; the GeoPackage is downloaded only when it is newer). The API checks
at start and every 6 hours whether an import is newer than its last sync
(`wanderland_import`), then creates, updates and deletes the routes; about
1.5 minutes for all 440, with a height profile from geo.admin per stage.
Routes that fail (geo.admin not answering) are tried again at the next
check; an import of fewer than 100 routes is refused and changes nothing.
The log line `official routes synced` counts what it did. To sync again
without a new import: `UPDATE wanderland_import SET synced_at = NULL`, then
wait for the next check or restart the API.

## Telemetry

The API and the web server send traces by OTLP when
`OTEL_EXPORTER_OTLP_ENDPOINT` is set (standard OpenTelemetry variables:
`OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES`, `OTEL_SDK_DISABLED=true` to
switch off). On rk1 they reach the collector DaemonSet on their node
(`http://$(HOST_IP):4318`, monitoring-system in the gitops repo), which
sends them to Tempo (`cluster/monitoring-system/tempo`, a week kept). Tempo
derives span metrics (`traces_spanmetrics_*`) and the service graph
(`traces_service_graph_*`) and writes them to Prometheus. In Grafana, a
trace links to its log lines in VictoriaLogs and to the request rate and
latency of its service; a VictoriaLogs line with a `trace_id` links to the
trace («Trace»). Metrics are served for
Prometheus on their own port when `ALVYO_METRICS_LISTEN` (API, e.g. `:9464`)
and `METRICS_PORT` (web) are set; kube-prometheus-stack scrapes them through
`cluster/alvyo/servicemonitor.yaml` (`http_server_request_duration_seconds`
of the API, `http_server_request_duration` of the web, `db_client_*`, `go_*`).
Logs are JSON on stderr; the collector reads them into VictoriaLogs (the
JSON stays in `_msg`); lines of a request carry `trace_id`. Locally: `docker run -p 4318:4318
otel/opentelemetry-collector-contrib` with a debug exporter shows the traces.

## Moderation

```sh
cd /srv/alvyo/infra
docker compose -f compose.prod.yaml exec api /alvyo user ban <username>     # ends sessions, makes routes, journeys and collections private
docker compose -f compose.prod.yaml exec api /alvyo user unban <username>
docker compose -f compose.prod.yaml exec api /alvyo user role <username> moderator   # sees "Moderation" in the app
docker compose -f compose.prod.yaml exec api /alvyo route unpublish <route-id>
```

## Verified locally (2026-09-22)

The production stack ran on `DOMAIN=localhost` (Caddy's internal CA): pages,
API, tiles and security headers through Caddy; signup with mail delivery; the
cross-origin check; `Secure; HttpOnly; SameSite=Lax` session cookie; routing;
`backup.sh` + `restore-check.sh`; `refresh-graph.sh` (import 2 min, swap,
routing works again within seconds); `user ban` blocking login.
