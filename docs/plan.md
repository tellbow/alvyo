# Plan

What odysgeh is for, what is done and what comes next. Keep it current:
when a requirement is done or changes, update this file in the same commit.
Status: 2026-09-24.

## Goal

Our own hiking platform for Switzerland, to replace Komoot (bought by Bending
Spoons in 2025: most of the staff laid off, device sync behind a paywall,
higher prices):

- plan hikes A→B on the swisstopo national map, with the official Swiss
  hiking time, the SAC grade (T1–T6), surfaces and an elevation profile;
- share them, publicly or by link and invitation;
- multi-week stage journeys, with public transport to and from each stage;
- an app that navigates offline on the national map and records hikes.

Decisions and their reasons: [ADR 0001](adr/0001-own-app-stack-license.md)
(our own app rather than extending wanderer; Flutter, SvelteKit, Go,
PostGIS; AGPL-3.0), [0002](adr/0002-elevation-and-hiking-time.md) elevation
and hiking time, [0003](adr/0003-graphhopper.md) GraphHopper,
[0004](adr/0004-offline-maps.md) offline maps. Hiking times match the
official figures: [hiking-time.md](hiking-time.md).

## Milestones

| | What | Status |
|---|---|---|
| M1 | Web planner, journeys and stages, sharing, GPX export, public pages, deployment | done (0.1.0) |
| M2 | Follows and feed, likes, comments, reports and moderation, photos, import (GPX, KML, TCX, FIT, Komoot), discovery, passkeys and OpenID Connect, French and Italian | done (0.1.0); open items in the backlog |
| M3 | iOS app: offline maps, navigation, recording, Apple Watch import, spoken turns, journeys | done up to 0.4.0; open items in the backlog |
| M4 | Extras: weather, points of interest, PDF stage sheets, 3D, closures | open |

## Releases

A `v*` tag builds the images; Flux deploys them
([operations.md](operations.md)). Production: https://odysgeh.tellbow.ch.

| Version | Date | What |
|---|---|---|
| 0.1.0 | 2026-09-23 | M1 and M2 |
| 0.2.0 | 2026-09-23 | Offline maps (PMTiles packs built by the API); the iOS app lists routes, shows them on the national map and saves them offline |
| 0.3.0 | 2026-09-23 | Place search, the list of points, dragging the line; in the app: navigation, recording and upload of hikes, Apple Watch import |
| 0.4.0 | 2026-09-23 | Spoken turn-by-turn navigation (turns from GraphHopper map matching); journeys in the app, all stages saved offline at once |
| 0.5.0 | 2026-09-24 | A GPX file into a stage (requirement 6), dragging the line onto another path (9), tags (10), a map of all my hikes (11), planning a multi-day hike (8), a long track into stages (7); fixes from a review of all parts: ways into accounts registered with someone else's address, internal errors hidden, crafted photos, offline pack builds and cleanup, recording robustness and loop routes in the app, planner clicks, retries and saving |

## Requirements

From the project owner, numbered in the order given: 1–5 added on
2026-09-23, 6–11 on 2026-09-24.

### Done

1. **Place search in the planner** (0.3.0). Start, destination and
   intermediate points by name as well as by clicking the map: our stops and
   huts together with the geo.admin search (names, places, addresses).
2. **Intermediate points as a list** (0.3.0). Add by search or map, remove,
   reorder; only the affected legs are computed again.
3. **Drag the route line** (0.3.0). Press, hold and drag the line onto
   another trail: a new point there, the two legs snap to the path network
   (e.g. Gitschenen → Brisenhaus SAC). Mouse only; touch is not built yet.
4. **Navigation in the app** (0.3.0; spoken turns 0.4.0). Position on the
   offline map, distance and time done and to go (Swiss hiking time at the
   hiker's pace), off-route warning, recording in the background, upload as
   a hike linked to the route, turns shown and spoken.
5. **Tracking with a watch** (0.3.0). Hikes recorded with the Apple Watch's
   Workout app are imported from Apple Health (works with a free Apple ID).
   A watchOS app of our own remains an option.
6. **A GPX file into a stage** (0.5.0). In the journey editor, «Datei
   importieren» gives a stage its route from a GPX, KML, TCX or FIT file in
   one step (`POST /journeys/{id}/stages/{stage}/import`, several tracks
   joined); a stage's route is only replaced after asking.
9. **Dragging the line: a point, or a different path** (0.5.0). A switch in
   the planner («Beim Ziehen: Zwischenpunkt / anderer Weg», remembered in
   the browser; Alt/⌥ flips it for one drag). «Anderer Weg» keeps the points:
   the leg takes the GraphHopper alternative passing closest to the release
   point, or, if none comes within 100 m, the path through it. The point is
   kept on the leg's end anchor (`through`), drawn as a small dot on the
   line; a double-click on it gives the shortest path back. GraphHopper 11
   offers alternatives with the CH profiles once its factors are loosened
   (paths up to twice as long, sharing up to 80 %), in about 30 ms.
10. **Tags** (0.5.0). Routes (recorded hikes included), journeys and
    collections carry up to 20 tags of 40 characters, kept as typed and
    compared without case (`tags text[]`, GIN index on `lower_tags(tags)`);
    stage routes have their journey's. Owners and editors set them like the
    title; they are shown with the item wherever it is seen. `GET /me/tags`
    lists the user's own tags with counts for suggestions. Web: a tag field
    in the route editor, on journeys and on collections; chips in the lists
    filter them (`?tag=`). App: tags shown in the lists.
11. **All my hikes on one map** (0.5.0). `GET /me/map`: one's routes,
    journeys (all their stages) and recorded hikes in the map view, filtered
    by kind, tags (any of them), distance, hiking time (at one's pace) and
    SAC grade, each a range with optional ends; for journeys the whole
    journey or, on request, the longest stage. Routes and journeys shared
    with me behind a switch; collections' items are not included. At most
    200, nearest to the centre first, lines simplified by zoom. Web:
    «Karte» on «Meine Routen» (`/routes/map`): lines coloured by kind or
    SAC grade, the list of what is in view, the filters in the address. An
    overview map in the app is a possible follow-up.
8. **Plan a multi-day hike from start, destination and days** (0.5.0).
   «Etappentour planen» (`/journeys/plan`): start, destination and points
   to pass, the number of days or the hours per day (at one's pace), an
   optional maximum per day (else 1.25 × the time per day, at least 1 h
   more), the profile, and the kinds of places preferred for the nights
   (huts, hotels and guest houses, campsites, a stop to travel home).
   `POST /journeys/plan` routes the whole way, takes the places within
   1 km of the line (per 250 m and kind the nearest) and picks the day ends
   by dynamic programming: each day's hiking time close to the target,
   under the maximum where possible, other kinds only where the preferred
   ones fit badly; a place off the line gets the way there in the evening
   and back in the morning. Each day offers the nearest place before and
   after as alternatives; huts show a hint to check opening and booking and
   their website where OSM knows it (`places.website`, from `make
   places-import`). `POST /journeys` with `stages` creates the journey with
   the routes, places and accommodation in one go. Live: Gaflei → Elm in
   three days ends in Sargans and Weisstannen, as the Via Alpina does
   (planned in about 3.5 s).
7. **One long GPX file into several stages** (0.5.0). In the import
   dialog, «Als Etappentour, in N Etappen» for any file (several tracks
   are joined). The preview lists per stage the length, time, ascent and
   where it ends; nothing is created before «Etappentour erstellen»
   (`POST /imports/stages`, then `POST /journeys` with the stages). Times
   are read from GPX, TCX, KML and FIT: a pause of 5 hours or more is a
   night, and a recording with nights proposes as many stages as days,
   split there, each ending at the nearest place within 400 m. Another
   number of stages, or a file without times, is split as in 8.

### Open

None: the next work comes from the backlog.

## Backlog

- Planner: dragging the line on touch screens.
- App: mark a stage as done after hiking it; recordings tied to the account
  (after logging in as someone else, pending hikes upload to the new
  account); starting a hike on another route ends the current one without
  asking.
- Community and moderation: moderators opening unlisted reported items;
  editing comments and replies; shadow-ban.
- Routes: revisions; privacy zones (start and end of recorded hikes hidden);
  a border buffer for routes near and across the border; the routing gap at
  Chamanna Jenatsch.
- Photos in HEIC.
- Journeys: two editors changing a stage at the same time overwrite each
  other (no version check on stages); cancelled trains and buses are not
  shown in connections (OJP).
- Web: choosing from some drop-downs with the keyboard acts on the first
  option (the choice acts on change).
- Operations: backups are kept on the cluster only; an off-site copy is
  missing.
- Texts: the French and Italian texts to be reviewed by a native speaker.
- M4: MeteoSwiss weather, highlights and points of interest, PDF stage sheets,
  3D terrain, closures, self-hosted Swiss Map Raster 25, full «how to get
  there» by public transport.

## Not tested on devices

What only a phone or a real hike can show, and what is still open there:
[manual-tests.md](manual-tests.md).
