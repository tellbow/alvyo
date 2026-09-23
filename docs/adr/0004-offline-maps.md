# ADR-0004: Offline maps as server-built PMTiles packs

Status: accepted (2026-09-23)

## Decision

The API builds an offline map ("pack") per route or journey: the national map
(`ch.swisstopo.pixelkarte-farbe`) and the hiking trails
(`ch.swisstopo.swisstlm3d-wanderwege`) within 1 km of the line, zoom 10–16.
Each layer becomes one PMTiles file (`api/internal/packs`). The app asks the
API to build the pack, polls its status, then downloads the two files and shows
them through MapLibre `pmtiles://file://…` raster sources.

- Tiles come from our tile cache (`/tiles/wmts/…`), so swisstopo sees each
  tile at most once per cache lifetime. The builder paces itself to 40
  tiles/s, below the cache's limit of 60 requests/s per address.
- The pack key hashes the line (and the zoom and buffer), not the title or
  version. Renaming a route keeps saved packs valid; changing its line gives a
  new key, and the app offers to update.
- Packs are rebuilt on demand. They are kept for 7 days after their last
  build or download, at most 512 MiB in total, in the API cache directory.

## Why

- MapLibre's native offline regions are rectangles, and the iOS SDK downloads
  their tiles one after the other. Covering a route needs many small regions,
  and saving one stage did not finish within 5 minutes in the simulator (a few
  tiles per second while the tile cache was cold).
- A pack is two files over one connection each, which suits a phone. The API
  answers Range requests, so interrupted downloads can resume (the app does
  not use this yet).
- Sargans–Weisstannen (19.3 km): 381 tiles per layer, 10.7 MB national map and
  1.9 MB trails. Building and downloading took about 20 s with a warm tile
  cache.

## Consequences

- The app stores the route with its pack, so saved routes open without a
  connection. Outside the corridor and below zoom 10 the offline map is empty.
- Long journeys are limited to 60,000 tiles per pack; beyond that, stages are
  saved one by one.
