# Operations

Alvyo was called odysgeh before 0.8.0. Since 2026-10-09 the database and
its user are called alvyo as well. An installation from before renames them
once, with the api stopped (a role cannot rename itself, hence the helper):

```sh
docker compose -f compose.prod.yaml stop api
dc="docker compose -f compose.prod.yaml exec -T db"
$dc psql -U odysgeh -d postgres -c 'CREATE ROLE rename_admin SUPERUSER LOGIN'
$dc psql -U rename_admin -d postgres -c 'ALTER ROLE odysgeh RENAME TO alvyo' -c 'ALTER DATABASE odysgeh RENAME TO alvyo'
$dc psql -U alvyo -d postgres -c 'DROP ROLE rename_admin'
docker compose -f compose.prod.yaml up -d
```

## Server

One VPS in Switzerland or the EU is enough to start:

| | Minimum | Why |
|---|---|---|
| CPU | 4 vCPU | GraphHopper import (weekly), API |
| RAM | 8 GB | GraphHopper serves with ~3 GB heap, imports need ~4 GB more |
| Disk | 40 GB | OSM extracts 4.9 GB (Switzerland, Liechtenstein and the neighbouring regions), graph 0.7 GB (three during a refresh), trail data 0.6 GB, tile cache up to 60 GB (`infra/tilecache/nginx.conf`, `max_size`) — size the cache to the disk; photos about 0.5 MB each (at most 1000 per person), plus 3 copies in the backups; offline map packs at most 512 MiB in the API cache (ADR-0004) |

Docker with the Compose plugin, ports 80/443 open, a DNS record for the domain.

### Outbound connections

The API calls these services; allow them if egress is restricted:

| Host | For |
|---|---|
| `api3.geo.admin.ch` | Elevation profiles (legs beyond the border, or all without `ALVYO_SWISSALTI3D_DIR`), place search in the planner |
| `api.opentransportdata.swiss` | Connections (OJP), only if `ALVYO_OJP_TOKEN` is set |
| `accounts.google.com`, `appleid.apple.com` | Sign-in providers (`ALVYO_OIDC_PROVIDERS`): discovery, keys, tokens, and Apple's revocation when an account is deleted |
| `api.github.com` | Bug reports («Fehler melden») as issues, only if `ALVYO_GITHUB_TOKEN` is set: a fine-grained token for the private `tellbow/alvyo-feedback` (`ALVYO_GITHUB_REPO` for another) with «Issues: read and write» and «Contents: read and write» (screenshots are committed under `screenshots/`). Without it reports are only kept in the database, without screenshot. |

Requests to geo.admin that fail with 429, 5xx or no answer are retried as
[geo.admin asks](https://docs.geo.admin.ch/get-started/retry.html):
truncated exponential backoff (1, 2, 4 … s) with up to 1 s of jitter (the
API's heights, `swissalti3d.py`, and the imports' `download.sh`; curl's own
`--retry` has no jitter).

The jobs fetch from `data.geo.admin.ch` (weather-precip and the imports,
alti-import the swissALTI3D tiles),
`download.geofabrik.de` (graph-refresh) and `s3.WAW3-2.cloudferro.com`
(snow-cover: Copernicus's snow cover, EEA's public bucket).

The tile cache fetches from `wmts.geo.admin.ch` and `tiles.mapterhorn.com`
and checks their certificates (`proxy_ssl_verify`; the cluster has its own
copy of the configuration in the deployment repository).

Reverse proxies in front of `/api` must accept request bodies of 22 MB
(file imports: 20 MB plus form overhead).

### Sign-in providers (optional)

Besides passwords, people can log in through OpenID Connect
providers you configure, e.g. Google:

1. Google Cloud console → APIs & Services → Credentials → OAuth client ID
   (web application), redirect URI
   `https://<DOMAIN>/api/v1/auth/oidc/google/callback`.
2. In `infra/.env`: `OIDC_PROVIDERS=google`, `OIDC_GOOGLE_CLIENT_ID=…`,
   `OIDC_GOOGLE_CLIENT_SECRET=…` (compose.prod.yaml passes them on).
   On the cluster: `ALVYO_OIDC_GOOGLE_CLIENT_ID` and
   `ALVYO_OIDC_GOOGLE_CLIENT_SECRET` in `alvyo-secret` (sops-encrypted in
   the deployment repository), the provider list, name
   and issuer in `configmap.yaml`. A provider listed without its secret
   stops the API from starting: the keys go in first.
3. Check: `GET /api/v1/auth/providers` lists it, the login page shows
   «Mit Google anmelden».

Sign in with Apple (a paid Apple developer account; Certificates,
Identifiers & Profiles):

1. Identifiers: the App ID `ch.tellbow.alvyo` with «Sign In with Apple»
   (primary App ID) and «Associated Domains» (universal links); its
   server-to-server notification endpoint
   `https://<DOMAIN>/api/v1/auth/apple/notifications`.
2. Identifiers → Services IDs: one for the website (`ch.tellbow.alvyo.web`)
   with «Sign In with Apple», domain `<DOMAIN>`, return URL
   `https://<DOMAIN>/api/v1/auth/oidc/apple/callback`.
3. Keys: a key with «Sign In with Apple»; the .p8 file can be downloaded
   once. Services → «Sign in with Apple for Email Communication»: the
   sender (`ALVYO_MAIL_FROM`), whose domain must pass SPF, or Apple's relay
   drops mails to hidden addresses.
4. Configuration: `ALVYO_OIDC_PROVIDERS=google,apple`,
   `ALVYO_OIDC_APPLE_NAME=Apple`,
   `ALVYO_OIDC_APPLE_ISSUER=https://appleid.apple.com`,
   `ALVYO_OIDC_APPLE_CLIENT_ID` (the Services ID), `_TEAM_ID`, `_KEY_ID`,
   `_APP_ID` (the bundle id, for the app's own sign-in) in `configmap.yaml`;
   `ALVYO_OIDC_APPLE_KEY` (the .p8 file's contents, PEM) in `alvyo-secret`,
   passed on by its own `secretKeyRef` in `api-deployment.yaml` (the API
   takes the secret's keys one by one).
   No client secret: the API signs one with the key for each call. With
   Compose: `OIDC_APPLE_CLIENT_ID`, `OIDC_APPLE_TEAM_ID`,
   `OIDC_APPLE_KEY_ID`, `OIDC_APPLE_APP_ID`, `OIDC_APPLE_KEY` in
   `infra/.env`.

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
- A password reset ends all sessions and removes provider sign-ins
  and access tokens: whoever resets takes the account over, also
  from someone who signed up with another person's address.
- A session ends after 30 days without use and 180 days after the login at
  the latest. «Auf allen anderen Geräten abmelden» (account page, the app's
  profile) ends all others.
- Personal access tokens (`alvyo_pat_…`, «Konto») let AI assistants and
  `alvyo-cli` read an account: GET requests and the MCP endpoint
  `/api/v1/mcp`, which needs nothing configured (it is under `/api`, so the
  ingress passes it on). Only their SHA-256 is stored, in
  `access_tokens`; a banned account's tokens stop working. Setting up an
  assistant: [mcp.md](mcp.md).

## First deployment

```sh
git clone https://github.com/tellbow/alvyo.git /srv/alvyo
cd /srv/alvyo
make osm-fetch                          # OSM extracts: Switzerland, Liechtenstein, 15 km beyond
cp infra/.env.example infra/.env        # fill in DOMAIN, POSTGRES_PASSWORD, SMTP, CONTACT_EMAIL, OPERATOR_*
cd infra
docker compose -f compose.prod.yaml up -d --build   # first start: GraphHopper imports ~2 min
docker compose -f compose.prod.yaml run --rm tlm-import   # official trail network, once a year
docker compose -f compose.prod.yaml run --rm places-import   # stops, huts, accommodation
docker compose -f compose.prod.yaml run --rm wanderland-import   # the official routes
```

Caddy obtains the TLS certificate on the first request to `https://$DOMAIN`.
Set `VERSION` in `.env` to the deployed git SHA (`git rev-parse --short HEAD`);
the About page shows it next to the source link (AGPL §13).

Before going public:

- Set `OPERATOR_NAME` and `OPERATOR_ADDRESS` (on the cluster
  `PUBLIC_OPERATOR_NAME` and `PUBLIC_OPERATOR_ADDRESS` of the web
  deployment): the About page then names who answers
  for the site, as data protection law asks.
- Make the GitHub repository public: the About pages link its source (AGPL
  §13), NOTICE and the scripts that make the OpenStreetMap databases (ODbL).
  Bug reports stay private either way: they go to `tellbow/alvyo-feedback`.
- E-mail swisstopo (geodata@swisstopo.ch) about the expected tile volume:
  the terms allow restricting "excessive use" (about 20,000 users a day in
  a web application count as fair use).
- The terms and credits of every source: [licensing.md](licensing.md).

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
by the API within a minute. The cluster deployment's backups and how a
restore goes, by what was lost: [restore.md](restore.md).

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

The `geodata` volume (15 GiB) holds about 7.5 GB (2026-10-12): OSM 4.9 GB,
the graph and its rollback copy 0.7 GB each, swissTLM3D 0.6 GB, the
elevation cache 0.2 GB, Wanderland and places 0.2 GB. The weekly
`graph-refresh` (Monday 02:00 UTC) rewrites about 6 GB of it, and Longhorn
counts freed blocks as used until the filesystem is trimmed: the
Longhorn RecurringJob `filesystem-trim` therefore runs daily at
04:00 UTC. Weekly, it left the volume's actual size at 88 % for six days
and fired `LonghornVolumeUsageWarning` (over 80 %). A trim by hand: Longhorn
UI, the volume, «Trim Filesystem».

The `alti` volume (10 GiB, ReadWriteOnce) holds swissALTI3D as tiles,
about 6.3 GB ([ADR-0005](adr/0005-own-copy-of-swissalti3d.md)). The API
mounts it read-only at `/data/alti` (`ALVYO_SWISSALTI3D_DIR`); without tiles
there it asks geo.admin as before. The CronJob `alti-import` writes it
monthly and must run on the API's node (pod affinity), as the volume is
ReadWriteOnce. The first run fetches all 43 650 tiles (about 48 GB, about
5 hours) and keeps `index.json` along the way, so an interrupted run goes
on where it stopped; start it by hand: `kubectl create job --from=cronjob/alti-import alti-import-first`.
Later runs read swisstopo's catalogue (about 5 minutes) and fetch only the
renewed tiles. No snapshots needed: the import can always build it again.

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

The release also attaches `alvyo-cli` ([mcp.md](mcp.md)) for Linux, macOS
and Windows (amd64 and arm64) with their SHA-256 sums, built with the tag
as its version.

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
OSM data, 1 min per CH profile; on the cluster 11 min with a 4 GB heap, 4.7 GiB of
memory). Routes are found as before; the turns of
map matching are as many as before on GPS tracks (54 against 55 on 20
noisy tracks).

The OSM data reaches 15 km beyond the border (requirement 31): `fetch-and-merge.sh`
downloads about 3.4 GB of neighbouring extracts (kept, so later runs download
only what changed) and cuts them with `osmium extract`, which needs up to
3.7 GiB of memory. Geofabrik's regions are not all from the same day, so
`merge-extracts.sh` keeps only the newest version of an object on the border
(two versions made the graph import fail on 2026-10-19). With them the data
volume holds about 4.9 GB of OSM files
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
switch off). On the cluster they reach the collector DaemonSet on their
node (`http://$(HOST_IP):4318`), which sends them to Tempo (a week
kept). Tempo derives span metrics (`traces_spanmetrics_*`) and the service graph
(`traces_service_graph_*`) and writes them to Prometheus. In Grafana, a
trace links to its log lines in VictoriaLogs and to the request rate and
latency of its service; a VictoriaLogs line with a `trace_id` links to the
trace («Trace»). Metrics are served for
Prometheus on their own port when `ALVYO_METRICS_LISTEN` (API, e.g. `:9464`)
and `METRICS_PORT` (web) are set; kube-prometheus-stack scrapes them through
a ServiceMonitor (`http_server_request_duration_seconds`
of the API, `http_server_request_duration` of the web, `db_client_*`, `go_*`).
Logs are JSON on stderr; the collector reads them into VictoriaLogs (the
JSON stays in `_msg`); lines of a request carry `trace_id`. Locally: `docker run -p 4318:4318
otel/opentelemetry-collector-contrib` with a debug exporter shows the traces.

GraphHopper times nothing per request itself. Its image carries the
OpenTelemetry Java agent, switched on by
`-javaagent:/opt/opentelemetry-javaagent.jar` in `JAVA_OPTS` (on the cluster,
not locally): spans `GET /isochrone`, `POST /route` and so on inside the API's
trace, and `http_server_request_duration_seconds` and `jvm_*` for
Prometheus on 9464 (`OTEL_EXPORTER_PROMETHEUS_HOST=0.0.0.0`, or the agent
listens on localhost only). The span metrics carry `server_address`, so the
time a client span waits splits by service (`graphhopper`, `db`,
`api3.geo.admin.ch`, `api.opentransportdata.swiss`).

The tile cache logs a JSON line per request: `request_time`,
`upstream_time` and `cache` (`HIT`, `MISS`, `EXPIRED`). PostgreSQL preloads
`pg_stat_statements` (`infra/postgis/Dockerfile`, migration 0037); the
slowest queries in total:

```sh
kubectl -n alvyo exec deploy/db -- psql -U alvyo -d alvyo -c "SELECT calls, round(total_exec_time) AS ms, round(mean_exec_time::numeric, 1) AS mean, left(query, 80) FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 20"
```

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
