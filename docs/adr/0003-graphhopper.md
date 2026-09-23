# ADR-0003: Self-hosted GraphHopper 11.0 for hiking routes

Status: accepted (2026-09-22)

## Decision

Route hiking legs with a self-hosted GraphHopper 11.0 (`infra/graphhopper/`) on
the Geofabrik extracts for Switzerland **and** Liechtenstein, merged with
osmium (`infra/data-import/fetch-and-merge.sh`). The Swiss extract does not contain
Liechtenstein, where e.g. Via Alpina stage 1 starts.

Two profiles, both with contraction hierarchies:

- `hike` — blocks `hike_rating > 3` (SAC T4+), prefers signed hiking routes
  (`foot_network` international/national ×1.7, regional/local ×1.5).
- `alpine` — allows up to T6, same network preference, lower speed on T5+.

Speeds only steer the route choice. Displayed durations come from the Swiss
hiking time formula (`swiss/hikingtime`), and elevation from swissALTI3D
(`swiss/elevation`), so GraphHopper runs without elevation data.

## Why

- `hike_rating` (OSM `sac_scale`) and `foot_network` (route relations) are
  built-in encoded values, and path `details` give per-segment SAC, surface and
  way type for the breakdowns.
- Apache-2.0, a single JVM process, and a small graph for CH + FL.
- The `pmtiles` elevation provider and per-request custom-model parameters are
  only on master (12.0, unreleased); we pin 11.0 and revisit when 12 ships.

## Measurements (2026-09-22, Apple M-series, Docker Desktop, `-Xmx6g`)

| | |
|---|---|
| Input `ch-fl.osm.pbf` | 550 MB (OSM data of 2026-09-21) |
| Graph | 3.11 M nodes, 3.88 M edges, 2 CH profiles (~3.05 M shortcuts each) |
| Import + CH preparation | 125 s |
| Peak heap during import | ~2.6 GB |
| Resident memory when serving | ~2.8 GB (container) |

Serving with `-Xmx3g` should be enough; imports need ~4 GB of headroom. On a
small VPS, build the graph elsewhere and copy `graph-cache/`.

## Observations

- `sac_scale` coverage in OSM is patchy: Gaflei → Pfälzerhütte (FL) returns
  `hike_rating = 0` (unknown) for the whole route, while trails in the Bernese
  Oberland carry values. SAC grades therefore fuse OSM with the swissTLM3D
  trail categories (ADR pending with `swiss/sac`).
- `osmium merge` drops the replication timestamp; the script copies it from
  the Swiss extract so `/info` reports the real data date.
