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
| next | — | On main since 0.4.0: fixes from a review of all parts (2026-09-24): ways into accounts registered with someone else's address, internal errors hidden, crafted photos, offline pack builds and cleanup, recording robustness and loop routes in the app, planner clicks, retries and saving |

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

### Open

Proposed order: 6 (small), 9 (planner only), 10 and 11 (tags, then the map
that filters by them), 8 (the day splitting), 7 (reuses 8's splitting).

#### 6. A GPX file into a stage

In the journey editor, a stage gets its route from an uploaded file (GPX,
KML, TCX, FIT) in one step. Today that takes two: import the file as a route,
then copy it into the stage («Aus meinen Routen übernehmen»).

- API: `POST /journeys/{id}/stages/{stage}/import` (multipart, like
  `/imports`), for editors. Several tracks in the file are joined
  (`imports.Join`), then `Importer.Content` → the stage's route. A stage that
  has a route keeps it unless the request says to replace it (409 as today
  otherwise). Counts per track against the import limit.
- Web: «Datei importieren» next to «Route planen» and «Aus meinen Routen
  übernehmen»; replacing a route asks first.
- Check: API test (the stage gets the route; start and end places, the gap to
  the previous stage and the journey totals follow; viewers get 403);
  Playwright: import a GPX into stage 2 of a journey.

#### 7. One long GPX file into several stages

A file with several tracks already becomes a journey with a stage per track.
A single long track (a multi-day route, or a recording of several days)
should be split as well.

- Where to split: at the nights of a recording (a gap of several hours in
  the time stamps); otherwise the user gives the number of days or the hours
  per day, and the line is split as in requirement 8: at huts, hotels,
  campsites or stops near it, into days of similar Swiss hiking time.
- Web: in the import dialog, «Als Etappentour, in N Etappen» with a preview
  (per stage: length, time, ascent, where it ends) before anything is
  created.
- Open: split at the nights of a recording without asking, or always show
  the preview first? (Proposal: always the preview.)
- Check: unit tests for the split (time gaps; days with places); API test: a
  three-day recording becomes three stages; Playwright: import with preview.

#### 8. Plan a multi-day hike from start, end and days

Give start, destination (optionally points to pass), the number of days or
the hours to walk per day, and the profile. odysgeh routes the whole way and
proposes a journey whose stages end where one can sleep: SAC and other huts,
hotels and guest houses, campsites, or a stop to travel home.

- Data: the places table holds about 850 huts, 5,400 hotels, guest houses
  and hostels, 530 campsites (OpenStreetMap) and 27,000 stops (BAV)
  (`make places-import`; counts of the dev database, September 2026).
- Sketch: route the whole way; take the overnight places within about 1 km
  of the line and their position along it; pick the day ends by dynamic
  programming so that each day's hiking time is close to the target and
  under a maximum, preferring the kinds of places chosen (e.g. huts). A
  place off the line gets a short leg to it in the evening and back in the
  morning. Each stage gets its start and end place and the accommodation.
- UI: a form «Etappentour planen»; a preview on the map with each day's
  numbers and place, the next place before or after as alternatives per day;
  «Erstellen» makes the journey.
- API: `POST /journeys/plan` returns a proposal without saving it; accepting
  creates the journey with its stages (new endpoint or the existing ones).
- Open: whether huts are open (season, booking) is rarely in OSM: show a
  hint to check, link the hut's website where known. Days or hours per day:
  either may be given.
- Check: unit tests for the split (synthetic line and places: target hours,
  maximum, preferences); API test with recorded GraphHopper answers; live:
  Gaflei → Elm in three days ends near Sargans and Weisstannen, as the Via
  Alpina stages do; Playwright: plan, accept, a journey of three stages with
  accommodation.

#### 9. Dragging the line: a point, or a different path

Today dragging the line always adds an intermediate point where it is
released. Wanted: the choice to move the whole leg between the two points
onto the other path instead, without a new point.

- UI: dragging adds a point by default; a switch in the planner («Beim
  Ziehen: Zwischenpunkt / anderer Weg») changes that, and holding Alt (⌥)
  while dragging uses the other way once. Alternative to decide: ask after
  each release, in a small menu with both choices.
- «Anderer Weg»: GraphHopper's alternative routes between the two points,
  taking the one that passes closest to where the line was released. If
  none comes near (about 100 m), route through the release point and keep
  it as a hidden shaping point (not in the list of points, small on the
  map), so the leg follows that path.
- To check: whether GraphHopper 11 offers alternative routes with our CH
  profiles, or needs the flexible mode (slower) for them.
- Check: Playwright: with the switch on, a drag leaves the points as they
  were and the leg passes near the release point; off, it adds a point as
  now.
- Related: dragging on touch screens (backlog).

#### 10. Tags

Routes, journeys and collections get tags, to sort one's own hikes: e.g.
«Winter», «mit Kindern», «Tessin», «Wunschliste». Collections stay the
curated, shareable lists; tags are quick labels to filter by.

- Model: a `tags text[]` column on routes, journeys and collections (GIN
  index), normalised (trimmed, case-insensitive when comparing, as typed
  when shown), at most 20 tags of 40 characters each. Stage routes use their
  journey's tags. Recorded hikes can have tags too.
- API: `tags` in create and update (owner and editors, like the title);
  `GET /me/tags` lists the user's tags with how often each is used, for
  suggestions.
- Web: a tag field with suggestions in the route and journey editors and on
  collections; tags as chips in the lists («Meine Routen», journeys,
  collections), a click filters by the tag.
- App: tags shown in the lists; filtering there follows with 11 if wanted.
- Open: are tags private labels of the owner, or shown to everyone who may
  see the item (public pages, discovery)? Proposal: shown with the item, as
  the title is, but only the owner's own tags are offered and filtered by.
- Check: API tests (set and replace, normalisation, limits, the tag list
  with counts, viewers cannot change tags); Playwright: tag two routes,
  filter the list by one tag.

#### 11. All my hikes on one map, with filters

An overview of all one's routes, journeys (all their stages) and recorded
hikes drawn on the map, narrowed by filters: tags, distance, hiking time and
difficulty, each as a range with optional ends (between x and y, more than
x, less than y).

- Builds on Discover (`GET /discover`: lines simplified for the map view,
  kind, hardest SAC grade, hiking time), which shows public items only.
  Either a scope on it (`scope=mine`, also routes shared with me) or its own
  endpoint `GET /me/map`, with the filters `tags` (any of them), `distance_min`,
  `distance_max`, `duration_min`, `duration_max`, `sac_min`, `sac_max` and
  `kind` (route, journey, recorded hike). Hiking time counts at the user's
  pace, as Discover does; for journeys distance and time are the whole
  journey's, with the longest stage as a further option.
- Web: a map page for «Meine Routen» (like Discover): lines coloured by kind
  or SAC grade, a list of what is in view next to it, the filters above
  (tag chips, two-handled sliders or number fields for distance and time,
  T1–T6 from and to). The address keeps the filters, to bookmark them.
  Clicking a line or list entry opens the item.
- Many items: the query is limited to the map view and simplifies lines by
  zoom, like Discover; above a limit the page asks to zoom in or narrow the
  filters.
- App: an overview map there too is a possible follow-up (not asked for).
- Open: several tags mean any of them (proposal) or all of them? Include
  items shared with me and collections' items by default, or behind a
  switch?
- Check: API tests for each filter and their combinations, bounds included;
  Playwright: with a tag and a distance range only the matching lines are
  drawn and listed.

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
