# ADR-0001: Own app on SvelteKit + Go + PostGIS + Flutter, AGPL-3.0-only

Status: accepted (2026-09-22)

## Context

Komoot (acquired by Bending Spoons in 03/2025) is the reference product. The
open-source alternative [wanderer](https://github.com/open-wanderer/wanderer)
(v0.20.0) was evaluated: it covers route planning (Valhalla), trail sharing and
community basics, but lacks the Swiss hiking time formula, SAC grades,
swisstopo maps (online and offline), stage-based journeys, public transport
and moderation. Its plugins can only import or send trails, and offline use and
navigation exist only in a beta Flutter app on an unmerged branch, so every
gap would require changes to its core.

## Decision

Build Alvyo as its own product:

- Web: SvelteKit (Svelte 5) + MapLibre GL JS, managed with bun.
- API: Go (huma, pgx, goose) on PostgreSQL + PostGIS.
- Routing: self-hosted GraphHopper (ADR-0003).
- Mobile (milestone M3): Flutter.
- License: AGPL-3.0-only. Code derived from wanderer (AGPLv3) may be reused
  with attribution in NOTICE and SPDX headers.

The first milestone is the web planner with journeys; until the app exists,
routes are navigated by exporting GPX to the swisstopo app.
