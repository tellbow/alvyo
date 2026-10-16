# Plan

What Alvyo is for, what is done and what comes next. Keep it current:
when a requirement is done or changes, update this file in the same commit.
Status: 2026-10-16.

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
| M2 | Follows and feed, likes, comments, reports and moderation, photos, import (GPX, KML, TCX, FIT, Komoot), discovery, passkeys (removed on 2026-10-15) and OpenID Connect, French and Italian | done (0.1.0); open items in the backlog |
| M3 | iOS app: offline maps, navigation, recording, Apple Watch import, spoken turns, journeys, planning | done up to 0.9.0; open items in the backlog |
| M4 | Extras: weather, points of interest, PDF stage sheets, 3D, closures, how to get there | done (0.16.0); the own 1:25 000 map in the backlog |

## Releases

A `v*` tag builds the images; Flux deploys them
([operations.md](operations.md)). Production: https://alvyo.tellbow.ch.

| Version | Date | What |
|---|---|---|
| 0.1.0 | 2026-09-23 | M1 and M2 |
| 0.2.0 | 2026-09-23 | Offline maps (PMTiles packs built by the API); the iOS app lists routes, shows them on the national map and saves them offline |
| 0.3.0 | 2026-09-23 | Place search, the list of points, dragging the line; in the app: navigation, recording and upload of hikes, Apple Watch import |
| 0.4.0 | 2026-09-23 | Spoken turn-by-turn navigation (turns from GraphHopper map matching); journeys in the app, all stages saved offline at once |
| 0.5.0 | 2026-09-24 | A GPX file into a stage (requirement 6), dragging the line onto another path (9), tags (10), a map of all my hikes (11), planning a multi-day hike (8), a long track into stages (7); fixes from a review of all parts: ways into accounts registered with someone else's address, internal errors hidden, crafted photos, offline pack builds and cleanup, recording robustness and loop routes in the app, planner clicks, retries and saving |
| 0.6.0 | 2026-09-24 | Live location for contacts with an overdue alert (12), protected areas along routes (13); keyboard drop-downs, stage versions, comment replies and edits, HEIC photos, dragging the line on touch screens; in the app: elevation profiles and ascent while hiking, recordings per account, asking before switching hikes, ticking stages off |
| 0.7.0 | 2026-09-24 | Search engines: titles, descriptions, canonical addresses, noindex for private pages, a sitemap and an address per language (/en/, /fr/, /it/ with hreflang); link-preview images of journeys and collections; compressed answers; map tiles refused while busy are asked for again; the draft logo on the web and as app icon |
| 0.8.0 | 2026-09-25 | Renamed from odysgeh to Alvyo: code, images (`alvyo-*`), `ALVYO_*` settings, the address alvyo.tellbow.ch (the old one redirects), the app as `ch.tellbow.alvyo`; the database, namespace and volumes keep the old name. The design of the Alvyo mock-up, light and dark after the system setting: colours, Figtree and Bricolage Grotesque, the Λ logo and icons, a new home page (public hikes, place search); in the app a floating bar (routes, journeys, record, Apple Watch, profile) |
| 0.9.0 | 2026-09-27 | Several ways to choose from (16): «Mehrere Wege vorschlagen» in «Etappentour planen», and a journey put together from them where they share a night; hours per day from … to, the days follow (17); huts, hotels and campsites on every map (15); in the app planning like on the website (18): «Route planen», «Etappentour planen» and «Entdecken», the huts layer, and the search on a page of its own; planning fixes: ways to night places start on the line (Thun → Zermatt failed), no nights at places near the line but far by path, no ferries and car trains (a new graph, operations.md), heights of legs without length; fixes from a review of all parts: a sign-in provider connected before the address was proven is dropped on a password reset, the client address behind the proxy, photo limits under concurrent uploads, offline packs of a route changed back, crashes in the multi-day planner and in turns, times without a zone in imports, the login redirect, stale plans in the web planner, recordings and live location in the app (hangs, a start cut off by iOS, loops), and faster deletes, reorders and pack builds |
| 0.10.0 | 2026-09-27 | Planning easier to find: «Route / Etappentour» at the top of both planners, a button on «Etappentouren»; collections filled from the collection itself («Route oder Etappentour hinzufügen …» searches one's own and shared routes and journeys) |
| 0.11.0 | 2026-09-28 | Deleting routes and journeys (19): «Löschen» in the app's menu of one's own, offline copies removed too, and in the website's lists; the most per day kept (20): no plan with a longer day, instead the fewest days that fit and «In N Tagen planen» |
| 0.12.0 | 2026-09-28 | Light or dark chosen on the website and in the app (21); the app's language (22); the app like the website (23): descriptions, photos, likes and comments, sharing, GPX, collections, reporting, a stage's details and public transport, the feed, profiles, what others shared, the map of one's tours and the account's settings |
| 0.13.0 | 2026-09-28 | From home and back by public transport (24): up to five homes, per journey and person the way from a home to the first stage and back from the last, leaving after or arriving before a time; the connections from the Swiss Open Journey Planner, the chosen one drawn on the map (not in the GPX) |
| 0.14.0 | 2026-09-28 | The website on a phone (25): a menu below 1280 px, the map above the panel below 768 px, a page for unknown addresses and errors, distances in the reader's language, the elevation profile folds away, start dots on the discover map; readable colours (26): grade badges, grey text, grade and stage colours that differ for colour-blind readers, 16 px fields on touch screens; in the app numbers like the website and profiles spanning the route's heights; recording without a route (27): the record button records a hike that becomes a route; names under the icons of the app's bar |
| 0.15.0 | 2026-09-28 | Privacy zones (28): others see recorded hikes without their first and last 500 m, on every page, map, GPX and preview; versions (29): the last 20 lines of a route, shown and restored on the website; the alpine way (30): a leg much longer by «Wandern» offers «Alpinwandern» for that leg alone (from the gap at Chamanna Jenatsch); across the border (31): routing and huts 15 km into the neighbouring countries |
| 0.16.0 | 2026-09-28 | Weather (32): MeteoSwiss's forecast at a route's start, highest point and end for a day chosen, and at each stage's highest point for its planned day; closures and shooting (33): closed trails and the army's shooting areas along routes, journeys and lines being planned; along the way (34): summits, viewpoints, waterfalls, water and shelters, a map layer «Unterwegs» and the list along a route; stage sheets (35): «Blatt zum Drucken» for routes and stages, A4 with map, profile, numbers, places, weather and connections; 3D (36): the terrain on the website's maps; how to get there (37): the way there and back for routes as for journeys, from a home or anywhere |
| 0.17.0 | 2026-09-29 | Travel only where a journey starts and ends (39); in the app: adding and planning stages (38), a journey's map (40), map layers and base maps (42, 43), changing a route on the map (49), inviting to collections (46); bug reports with a screenshot as GitHub issues (41); links into the app (45); along the way in more kinds, with icons, also on a route's map (47, 48, 56); closures and protected areas on request (50, 51); weather with MeteoSwiss's symbols and for any date, with the climate normals (52, 53); people who come along (55) and reminders before a journey (54) |
| 0.17.1 | 2026-09-29 | Every page of the website answered 500 (a package for bug report screenshots was not bundled); in the app «Unterwegs» shows its icons again (each map layer with its own source: the iOS map drops filters like «in») |
| 0.18.0 | 2026-10-02 | One's pace chosen (57): «Dein Tempo» on the account page and in the app's profile, hiking times at it in the app too; «Anderer Weg» shows the other ways while the line is dragged and takes the one let go on, or says why not, and adds no point (9); a saved route opens in the planner zoomed to it; stage sheets on one A4 page with a sharper map, «Unterwegs» grouping a town's fountains and restaurants; place search: names as searched and addresses first, broken labels and dropped passes fixed; bug report screenshots with the map in Safari; GPX file names keep dashes |
| 0.19.0 | 2026-10-02 | A route's page in tabs (58): one main action with GPX, «Merken» and «Teilen» beside it and the rest in a «⋯» menu; the four numbers in one strip; tabs «Übersicht», «Unterwegs» (a chip per kind), «Anreise» (a connection per line, three and then more) and «Fotos» that stay on top while scrolling; weather as today, tomorrow or a date; trail conditions in per cent, a bar only where kinds differ, a warning for a route off marked trails; the bug report button in the website's header; in the app the same numbers and tabs on a route's screen |
| 0.20.0 | 2026-10-02 | Journeys in tabs like routes (58): GPX, «Merken» and «Teilen» at the top, the rest in «⋯», the numbers and the progress, then «Etappen», «Übersicht», «Anreise», «Fotos» and the owner's «Teilen»; in the app the journey screen in the same tabs; the tab bar no longer scrolls up and down; the official trail network loaded on the cluster (it was missing: routes planned before show «Kein Wanderweg» until planned again) |
| 0.20.1 | 2026-10-02 | Routes planned while the official trail network was missing on the cluster graded anew: `alvyo route retrail` matches stored lines against the network again (17 routes in production no longer «Kein Wanderweg» with a guessed SAC grade); line, times and version stay |
| 0.21.0 | 2026-10-05 | Telemetry (59): OpenTelemetry traces of API and web by OTLP to the collector (dropped until there is a tracing backend), metrics for Prometheus through ServiceMonitors, `trace_id` in the API's logs; friends (60): requests both ways, a search for public profiles, invite links, private profiles for friends only, friends offered when sharing; hiked (61): «Gewandert» on routes and journeys, recorded hikes and finished journeys counted, «Geplant / Gewandert» in the lists, the map and the app |
| 0.22.0 | 2026-10-05 | Statistics with Google Analytics (62): the Google tag on alvyo.tellbow.ch with Consent Mode and a banner (cookies only after «Akzeptieren», changeable under «Über»), page views without the secrets of addresses; the privacy text names it |
| 0.22.1 | 2026-10-05 | Page views titled by their route (the title was empty behind the language prefix) |
| 0.23.0 | 2026-10-05 | A point along the way on the map (63); the app catches up (64): trail conditions, photos counted, planned or hiked on one's map, invite links; the icons along the way load without warnings; the header's controls with more contrast |
| 0.24.0 | 2026-10-05 | How far one gets (65): «Reichweite» in «Planen» and «Wie weit komme ich?» in the app, areas reached within 2, 4 and 8 hours; GraphHopper's graph with elevation; no turns announced from GPS jitter |
| 0.25.0 | 2026-10-07 | A shared collection shares its items (66, issue 17): by link or as public to view, with the people invited in their role (viewer or editor); how many items one cannot see instead of «Noch leer»; in the app a journey's stages keep the token it was opened with |
| 0.26.0 | 2026-10-07 | Rain radar and forecast on the map (67, issue 15): MeteoSwiss's radar of the last hour and the next 12 hours of ICON-CH1 on a timeline, on the website and in the app, from the new job weather-precip; removing a route or journey from a collection asks first |
| 0.26.1 | 2026-10-07 | The rain job reaches MeteoSwiss over IPv4 (it hung on the cluster's missing IPv6 route) |
| 0.26.2 | 2026-10-07 | The website's login answered 500 (the passkeys package was not bundled; since at least 0.17.1); search engines get the language start pages without a redirect (/fr, not /fr/) |
| 0.27.0 | 2026-10-07 | Recognising mountains with the camera (68, issue 16): «Berge erkennen» in the app names the summits in sight, also without reception |
| 0.28.0 | 2026-10-07 | «Berge erkennen» draws the nearer ridges as lines too, and the skyline no longer starts at the cells right next to one (on a summit they hid the view) |
| 0.29.0 | 2026-10-07 | The app's navigation tidied up (69): Entdecken, Planen, Touren and Profil; Rundtour and Zwischenziel, Reichweite back to the start (each way timed), importing files, Apple Watch hikes imported automatically, a tour to follow when recording; the app asks for notifications only when it schedules reminders |
| 0.29.1 | 2026-10-07 | Reichweite: «Zurück zum Start» off by default, its areas without the holes and steps between the paths; the layer menu on its map |
| 0.30.0 | 2026-10-08 | Fixes from a review of all parts: privacy — a live location of someone else's recorded hike, discovery and one's map no longer give away a hike's hidden start and end (the shown line is kept with the route), bug reports drop tokens from the address before the public issue, traces no longer hold the Komoot address and link tokens, a hike uploaded again is marked as hiked; overdue alerts are sent again when the mail server failed; ticking off a journey's stage no longer sends «beginnt morgen» each day, marking an unknown route or journey as hiked answers 404 instead of breaking the connection, stages from a track off the paths (a glacier) to a hut no longer fail, journey weather and protected areas load faster, missing forecast values no longer show as 0 °C or 0 mm; security: wrong passwords from elsewhere no longer lock one out, limits per address count an IPv6 network as one, a live location counts an e-mail per contact, moderators cannot ban admins or other moderators, the import preview is limited; website: leaving the planner with unsaved points asks first, logging in leads back to the page (with its filters), counts in the singular («1 Kommentar»), routes shared by link are no longer listed as «Privat», drop-downs that save act once the choice is made, late connection answers no longer overwrite newer ones, no other site can frame the pages; accessibility: readable error and like colours in dark mode, field borders and one focus ring with enough contrast, the map's buttons in the page's language and dark, the elevation profile and the route's numbers for screen readers, the planner announces its route, headings, a skip link, the current page in the menu, named point buttons, focus kept on confirmations and menus, arrow keys in tab bars; design: one radius scale, shared button styles, one route colour, the map's greys from the palette; app: a link opened during a hike leads back to it instead of a second recording, requests give up after 20 s and fall back to what is offline, Apple Watch workouts that cannot become routes are not uploaded again on every start, «Berge erkennen» takes a fresh position and says when the camera is not allowed, location taken away or switched off is said as such, a recording that cannot be saved says so, offline maps stop waiting for a build stuck on the server, the pace is kept for hikes started offline, «gibt es nicht (mehr)» instead of «Server nicht erreichbar» for deleted or private items; larger tap targets, readable warnings, the stats and headers with large text, VoiceOver for the rain timeline and elevation profile; maintenance: Go 1.26.6 and patched npm packages (no known vulnerabilities), CI checks vulnerabilities, workflows and secrets weekly too, actions pinned to commits, Renovate, images with SBOM and provenance, a GitHub Release per version, SECURITY.md; accounts: signing up no longer logs in or tells whether an address has an account (its owner gets an e-mail), the link from the e-mail names the account and logs in on «Bestätigen», logging in needs the address confirmed (a new link is sent), a password reset removes passkeys and Google/Apple sign-ins, sessions end 180 days after logging in at the latest, «Auf allen anderen Geräten abmelden» on the website and in the app; «Was ist neu» on the About page; the account page as wide as the other pages, ↑ ↓ for the points of a journey being planned, in the app one error state with «Nochmals versuchen» where it can help; release tags signed and checked, images signed with cosign, semgrep in CI |
| 0.31.0 | 2026-10-09 | The official routes (70): the 440 routes of Wanderland Schweiz (national, regional, local, barrier-free) as public routes and journeys of «Wanderland Schweiz», imported monthly and synced by the API, named with a link to SchweizMobil and the source, «Herkunft» in «Entdecken»; «Als eigene Route / Etappentour bearbeiten» copies any route or journey one can see; in the app a collection's map («Karte der Sammlung», issue 19); temperatures just below zero as 0 °C, not «-0 °C»; the four numbers of a long journey in two rows; the rain layer's job in compose.prod.yaml (issue 30); Go 1.26.9 and golang.org/x/net 0.60.0 (security fixes); README with features and screenshots, architecture diagrams (docs/architecture.md) |
| 0.32.0 | 2026-10-10 | AI assistants and the command line (71, issue 28): personal access tokens under «Konto» (website and app) that only read; an MCP server at `/api/v1/mcp` with nine tools (places, planning, reach, conditions, discovery, one's routes and journeys); `alvyo-cli`, also as a local MCP server for Claude Desktop, as binaries with each release; telemetry: GraphHopper traced and measured (OpenTelemetry Java agent), the tile cache's request time and cache status in its log, `pg_stat_statements` |
| 0.33.0 | 2026-10-10 | From «Reichweite» to planning (65, issue 13): a click or tap inside the areas says within how many hours and offers «Hierhin planen» (the planner with the start, that point and the same profile; in the app with «Zurück zum Start» as «Rundtour») or «Von hier aus neu»; the app's planner no longer breaks on a round trip's way back |
| 1.0.0 | 2026-10-15 | The first version for the App Store: the app's launch screen with the logo (light and dark), its permission texts in German, French and Italian, the Apple Health write text App Store Connect requires, and export compliance declared in Info.plist; the tile cache's layer map has room in its hash buckets |
| 0.34.0 | 2026-10-14 | The Android app, first part (72, issue 8): recording and navigation with the screen locked, spoken turns, warnings and reminders as notifications, links that open in the app, its APK with each GitHub Release; Apple Watch hikes import again (issue 33: the Watch's route can start before its workout), and «Nochmals» imports one once more as a new route; licences and credits (issue 25): every source credited where its data shows, the About page with all sources and their terms, NOTICE, the operator and a fuller privacy text, in the app «Über Alvyo» and a credit on every map; the Komoot import removed (its terms forbid it), Komoot's GPX export instead; the About page's sources with a space before their terms; SvelteKit 3, the planner's buttons wait for the page to be ready; the e2e tests run locally before each release instead of in CI; bug reports go to a private repository only the team sees, and the Android app's say android; release builds of the app no longer ask for a server; the repository is public, CI back on GitHub's runners |
| 1.1.0 | 2026-10-15 | Passkeys removed (migration 0038 drops them; accounts with only a passkey set a password with «Passwort vergessen?»); bug report screenshots are committed to the private feedback repository and shown in the issue instead of kept in the database (`alvyo bugs screenshots` moves the earlier ones once; the token needs «Contents: read and write»); a route's map shows every point its «Unterwegs» list shows, whatever kinds are switched off in the layer menu (feedback issue 1) |
| 1.1.1 | 2026-10-15 | `alvyo bugs screenshots` finds each screenshot's issue by the report's id instead of the number stored with it (the issues were numbered anew in the feedback repository) |
| 1.1.2 | 2026-10-15 | Migration 0039 drops the screenshot columns of `bug_reports` (moved to the feedback repository with 1.1.1); `alvyo bugs screenshots` is gone with them |
| 1.2.0 | 2026-10-16 | The app on the iPad (73): from 820 points wide a rail on the left instead of the floating bar, a map's panel beside it at full height (routes, journeys with their stages' map, Planen's modes, the discover map, a collection's map, the way there), lists and forms at most 720 wide; upright and on its side, also a phone on its side; App Store pictures for the iPad (`app/store`), the navigation picture in the app's colours; the `ipad-install` skill |

## Requirements

From the project owner, numbered in the order given: 1–5 added on
2026-09-23, 6–11 on 2026-09-24, 15–18 on 2026-09-26, 19–20 on 2026-09-27,
21–37 on 2026-09-28, 38–56 on 2026-09-29, 57–58 on 2026-10-02, 59–61
on 2026-10-05, 62 on 2026-10-05, 66 on 2026-10-07 (from issue 17), 67 on
2026-10-07 (from issue 15), 68 on 2026-10-07 (from issue 16), 69 on
2026-10-07 (a concept of the project owner), 70 on 2026-10-09 (from issue
14), 71 on 2026-10-09 (from issue 28), 72 on 2026-10-12 (from issue 8).

### Done

1. **Place search in the planner** (0.3.0). Start, destination and
   intermediate points by name as well as by clicking the map: our stops and
   huts together with the geo.admin search (names, places, addresses).
2. **Intermediate points as a list** (0.3.0). Add by search or map, remove,
   reorder; only the affected legs are computed again.
3. **Drag the route line** (0.3.0). Press, hold and drag the line onto
   another trail: a new point there, the two legs snap to the path network
   (e.g. Gitschenen → Brisenhaus SAC). On touch screens: hold the line a
   moment, then drag.
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
   while the line is dragged, the other ways between them show
   (`/routing/alternatives`), the one in reach stronger; let go on one, the
   leg takes it; elsewhere, or without another way, nothing changes and a
   message says why, and a click on the line adds no point (2026-10-02:
   before, the leg went through the release point when no way came within
   100 m, which looked like a new point). The way is kept on the leg's end
   anchor (`through`, a point where it differs most from the others),
   drawn as a small dot on the line; a double-click on it gives the
   shortest path back. GraphHopper 11
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
13. **Protected areas along a route** (0.6.0). Routes, journeys (with the
    stages) and the planner list the wildlife rest areas (Wildruhezonen; the
    Swiss National Park is one of them) and federal hunting reserves they
    cross: name, binding or recommended, the rule («Zutrittsverbot») and its
    period, highlighted when it applies today or on a planned day, with the
    canton's or BAFU's page. The rest areas come from the cantons and are
    published by BAFU only as a map layer, so the API asks geo.admin's
    identify service along the line (`POST /routing/areas`,
    `GET /routes/{id}/areas`, `GET /journeys/{id}/areas`; cached 30 days
    per line) instead of importing them. Web: overlays «Wildruhezonen» and
    «Eidg. Jagdbanngebiete»; the app lists them on route and journey
    screens.
12. **Live location for contacts, and an alert when overdue** (0.6.0).
    Contacts (name, e-mail, at most 10) are kept on the website under
    «Konto». Starting a hike in the app offers «Standort teilen» with the
    contacts chosen last time and the expected end (the route's hiking
    time at one's pace + 1 h, changeable); the contacts get the link
    (`/live/{token}`, no account needed: the route, the way so far, the
    last position and its time). The app sends a position a minute every 5
    minutes, and what it could not send once the connection is back;
    «Später» moves the end an hour; ending the hike ends the sharing (sent
    later if offline, so nobody is alerted about a hike that ended). A job
    every minute e-mails the contacts, and the hiker, once when a hike has
    not ended 30 minutes after the expected end, with the last position in
    WGS84 and LV95 and the emergency numbers; «Später» or the end after an
    alert sends an all-clear. The link works until 24 hours after the end;
    shares and positions are deleted 7 days after it. Starting needs a
    verified address and counts against the invitation limit (it sends
    e-mail). A reminder on the phone shortly before the expected end is a
    possible follow-up.
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

15. **Huts and accommodation on the map** (0.9.0). In the layer
    menu of every map, «Hütten» and «Hotels und Campingplätze» (off until
    switched on, remembered like the other layers) show the places of
    `make places-import` in view (`GET /places/in-view`; huts from zoom 8,
    the others from 10); a click shows the name, the kind and the website,
    and in the planner offers «Als Routenpunkt hinzufügen».
16. **Several ways to choose from, and a journey put together from them**
    (0.9.0). «Mehrere Wege vorschlagen» in «Etappentour planen»:
    `POST /journeys/suggest` proposes up to four ways between the points,
    each split into days as in 8. GraphHopper's alternatives stay in one
    valley (Thun → Zermatt: four of five over the Lötschenpass), so the
    other ways pass a village or hut to the side of the straight line,
    tried at 30 spots in about a second; kept are ways at most 1.5 times as
    long, not up a dead end and back, with at least a quarter of their
    own, the most different for their length first. Days end where an
    earlier way sleeps if that fits as well, so ways through the same
    village share the night there: «Ab hier weiter auf Weg N» goes on along
    the other way, and a journey put together so is created as in 8 (its
    nights are no longer moved one by one). Live: Thun → Zermatt in five
    days gives the Lötschenpass, the Gemmi (sharing the nights in Gampel
    and Kalpetran), the Gemmi and the Turtmanntal, and the Engstligenalp,
    in about 4 s. With it, planning in 8 improved: days no longer end at a
    place that is near the line but far by path (the Gfellalphütte: 170 m,
    20 km by path), the way to a place starts on the line also in a
    gallery, and routes no longer use ferries and car trains (the
    Lötschberg).
17. **Hours per day from … to, the days follow** (0.9.0). In
    «Etappentour planen», instead of the number of days, «Stunden pro Tag»
    from … to (at one's pace; `min_hours` and `max_hours` for
    `POST /journeys/plan` and `/journeys/suggest`): as few days as keep
    every day in the range, each close to the whole divided by their
    number; if no number of days fits, the closest, with the days too short
    or too long marked. Each suggested way gets its own number of days
    (Thun → Zermatt at 4–8 h: six or seven). A day can come out a few
    minutes over the most: the split estimates the way to a place, the
    stage has the real one.

18. **Planning in the app** (0.9.0). The app does what the website
    does for planning: «Route planen» (points by tapping the map, by the
    place search or from a hut's sheet, only the changed legs computed
    again, totals at one's pace, the elevation profile, saved and opened
    for offline use and navigation), «Etappentour planen» as in 8, 16 and
    17 (days or hours from … to, several ways, «Ab hier weiter auf Weg N»,
    created as a journey), «Entdecken» (public routes and journeys in view,
    starting at one's position if the app may already know it, filters for
    kind, hiking time and SAC grade, opened like one's own), and the huts
    layer of 15 on the route, navigation and planning maps. They need this
    release's API on the server.
19. **Deleting routes and journeys** (0.11.0). In the app, the menu
    of a route and of a journey of one's own offers «Löschen», after
    asking; what is saved of it offline goes too (a stage's route is
    deleted with its stage, on the website). On the website, the lists
    «Routen» and «Etappentouren» delete as well, besides the pages.
20. **The most per day is kept** (0.11.0). Asked for at most so many
    hours a day (with the number of days, or hours from … to), a plan with a
    longer day is no longer shown (Thun → Zermatt in three days at most 8 h
    gave a day of 21 h 50 min): `POST /journeys/plan` answers 422 with the
    fewest days that would fit (or none, with too few places to sleep);
    `/journeys/suggest` leaves out the ways that do not fit, and answers so
    if none does. Website and app say it, with «In N Tagen planen». Days
    moved by hand (`ends`) are only marked; up to 15 minutes over count as
    within, as the split estimates the way to a place.
21. **Light or dark, chosen** (0.12.0). Website and app follow the
    system's setting unless «Hell» or «Dunkel» is chosen: on the website in
    the header («Darstellung», kept in a cookie, so the page comes rendered
    in it), in the app in the profile (kept on the phone).
22. **The app's language** (0.12.0). In the profile: «Automatisch» (the
    iPhone's), Deutsch, English, Français or Italiano; for the account also
    the language of e-mails, as on the website.
23. **The app does what the website does**, where it makes sense on a phone
    (0.12.0). A route's and a journey's description, tags, owner,
    photos (from the camera or the library) and likes and comments with
    replies; a menu to change title, description, tags and visibility, to
    share (link, people invited as viewers or editors), to send the GPX,
    to add to a collection, to report and to delete. A stage's sheet: its
    day, status, accommodation, notes and transfer to change, the SBB
    timetable to the start and from the end, connections for a transfer by
    public transport and from the nearest stop to the start. The bar has
    «Neuigkeiten» (the feed) instead of the Apple Watch, which moved to a
    button above «Meine Routen». What others shared shows below one's own
    routes and journeys; profiles with following, blocking and reporting;
    collections, with «Karte der Sammlung»: all their routes and journeys on
    one map, each in its colour as on the website, a tap on a line opening
    it (issue 19); in the profile the map of one's tours, the e-mail
    notifications, the contacts for shared hikes, blocked people and
    deleting the account; signing up and a forgotten password open the
    website. Left to the website: moderation, imports (files, Komoot),
    sign-in providers, planning a route again on its map.
24. **From home and back by public transport** (0.13.0). Up to five
    homes in the account (a name and an address from the place search).
    For a journey, each person who can open it chooses for themselves a
    home to set off from before the first stage and one to return to after
    the last, leaving after or arriving before a time on the stage's day
    (on the website beside the stages and when planning, in the app from
    the journey and when planning). The connections come from the Swiss Open
    Journey Planner from and to the address (the walk to the stop included);
    arriving by a time, the latest that fits comes first. The chosen one is
    drawn on the map, rides dashed and walks dotted; it is never part of the
    GPX, and no one else sees the homes or times.

25. **The website on a phone, and what a review found.** From a review
    of the website's screens against the Web Interface Guidelines, on a
    computer (1440 px) and a phone (390 px), on 2026-09-28. Below 1280 px
    the header's links, language, theme and account are in a menu; below
    768 px the map pages show the map in the upper half and the panel below
    it, and list rows put the title on a line of its own (at 390 px every
    page was 1157 px wide). Also: a page for unknown addresses and errors
    in the reader's language; distances in the reader's language («19,3 km»
    in French), the unit never on a line of its own; «Speichern» stays at
    the bottom edge of the planner's panel; the points of the planner show
    their height; the ↑ ↓ × are 32 px (44 px on touch screens); «Belag» and
    «Wegtyp» are left out when nothing is known; the elevation profile
    folds away (folded at first on a phone); on the discover map each hike
    has a dot at its start; the photo viewer keeps the keyboard in it; the
    contact fields have visible labels; focus rings on the home page's
    search and the tag input.

26. **Readable colours, and numbers and profiles in the app.** From a
    second review on 2026-09-28 (ui-ux-pro-max: the website, and the app
    in the simulator at normal and large text; dataviz: the charts and
    their colours). Grade badges take dark text where white does not read
    (T1: 1.9:1, no grade: 2.5:1); `stone-500` is darker and text no longer
    uses `stone-400` (both checked in `palette.spec.ts`); fields on touch
    screens have 16 px text, so Safari does not zoom; T3 and T4 have new
    steps so that neighbouring grades differ (T4 and T5 differed by 5.8,
    OKLab ×100) and the profile's readout names the grade; the stage
    colours are ordered so that neighbours differ also for red-green colour
    blindness (web and app, `colors.spec.ts`); the app writes numbers like
    the website («19,3 km» in French, units and arrows never on a line of
    their own); the app's profile spans the route's heights instead of
    starting at 0 m, its labels with «m». The photo viewer's grey texts no
    longer turn dark on black in dark mode.

27. **Recording without a route, and the app's bar.** The record button
    in the middle of the app's bar only showed a message pointing to the
    routes; it now records a hike without a planned route: the map shows
    the position before «Aufzeichnung starten», then the track, the
    distance and the time. «Beenden» uploads the hike, which becomes a
    route like any other («Wanderung, 28.09.2026»), and opens it; offline
    it goes up later, and one too short or outside Switzerland and
    Liechtenstein is not kept, which the message says. A hike on a route
    still being recorded goes on on its route. Not shared live with
    contacts (that needs a route's expected end). From the review for 26
    too: the bar names its places under the icons («Routen», «Etappen»,
    «Neuigkeiten», «Profil»); «Planen» with its name instead of an icon
    that read as a filter; «Offline speichern» outlined, below «Wanderung
    starten».

28. **Privacy zones.** Others see a recorded hike (in the app, from the
    Apple Watch) from the first point more than 500 m from its start to
    the last point more than 500 m from its end: on the route page, in the
    GPX, the turns and the offline map, on the discover map, in «my map»
    and collections, and in link previews (always trimmed, as they are
    cached). The owner and editors see the whole line on the route page;
    on the maps only the owner. A hike too short for anything to be left
    shows no line to others. The route page says so, to the owner too.
    Photos taken in the hidden parts are in the gallery, not on the map.

29. **Versions.** Every save of a route's line keeps the line before, the
    last 20 per route, with when and by whom it was saved (title and
    visibility changes are no new version). On the website's route page
    the owner and editors open «Versionen»: an earlier version shows on
    the map with its profile and numbers, and «Wiederherstellen» makes it
    the route's line again (the line replaced becomes a version itself).
    Not in the app.

30. **Longer by the hiking profile.** From the gap at Chamanna Jenatsch:
    the trail is in the graph, but OSM grades 250 m of it T4, so «Wandern»
    (up to T3) goes round it, 16.7 instead of 1.1 km between points on
    either side (hiking-time.md). When a leg planned with «Wandern» is at
    most two thirds as long with «Alpinwandern» (and at least 1 km
    shorter), the planner says so under the leg, with the hardest grade
    from T4 on: «Mit «Alpinwandern» nur 1.1 km statt 16.7 km. Der kürzere
    Weg führt über T4.» «Diesen Abschnitt alpin planen» plans that leg
    alone with «Alpinwandern» (kept with the route; «Wieder als
    Wanderung» undoes it), on the website and in the app.

31. **Across the border.** Routing reaches 15 km beyond Switzerland and
    Liechtenstein (Chamonix, the Aosta valley, Como, the Black Forest,
    Vorarlberg, the Vinschgau): the OSM extracts of the neighbouring
    regions, cut to that strip (`infra/data-import/border.geojson`), join
    the graph, with their huts. swisstopo's heights reach that far. The
    covered box (5.7–10.7° E, 45.65–47.95° N) takes points, imports and
    recorded hikes there; the texts say «bis 15 km über die Grenze».

33. **Closures and shooting.** Along a route, a journey's stages and a line
    being planned, with the protected areas: closed hiking trails the line
    runs along for at least 50 m (ASTRA's «Sperrungen Wanderwege», from
    the cantons' trail organisations; not the detours, not paths only
    crossed), with reason and dates, and the army's shooting areas it
    crosses, with the days and hours announced and the number to call.
    Only what is not over; highlighted on today or a planned day. From
    geo.admin, kept for an hour. Website and app.

36. **3D.** A button on the website's maps shows the terrain in 3D (seen
    from the side; flat and from above again with the same button), also
    after changing the base map. The terrain comes from Mapterhorn's open
    terrain tiles (swissALTI3D among their sources) through the tile cache,
    like swisstopo's tiles. Not in the app.

32. **Weather.** MeteoSwiss's local forecast (open data, for every
    postcode, weather station and selected mountain point), loaded once an
    hour: on a route's page the lowest and highest temperature and the
    precipitation with its likely range at start, highest point and end,
    for a day chosen from the next ones; on a journey's page, at each
    stage's highest point for its planned day. Each place takes the
    forecast point within 15 km most like it (distance plus 10 m per metre
    of height difference). Website and app.

35. **Stage sheets.** «Blatt zum Drucken» on a route's page and on each
    stage of a journey: a page for A4 («Drucken oder als PDF sichern»),
    light also in dark mode, without menu and buttons on paper. The line
    on the national map with the hiking trails (drawn once as an image),
    the profile, the numbers, what lies along the way (all of it) and the
    weather of a day chosen (the stage's planned day, else today); for a
    stage also start, end, accommodation and notes, and the connections of
    that day: from home before the first stage and home after the last (as
    chosen for the journey), and a transfer by public transport from the
    previous stage; for a route the way there and back chosen for it.
    Website only.

37. **How to get there.** For routes as for journeys (24): the way by
    public transport to the start and back from the end, from one of
    one's homes or from anywhere (a place found by the search, kept with
    its name), leaving after or arriving before a time; the connections
    drawn on the map. A route has no day of its own: its connections are
    those of the day chosen (today at first). Each person's own, on the
    website and in the app.

34. **Along the way.** Named summits (with their height), viewpoints,
    waterfalls, drinking water and shelters (not those at bus stops) from
    OpenStreetMap, imported with the huts into a table of their own (not
    offered as stage starts and ends): a map layer «Unterwegs» from zoom 12
    on the website and in the app, a tap names them; on a route's page the
    ones within 200 m of the line, in the order they come, with the
    distance from the start (the first ten, the rest on request).

38. **Stages added to a journey in the app.** «Etappe hinzufügen» below
    the stages (owner and editors) adds one and opens the planner for it,
    starting where the stage before ends; a stage without a route opens the
    planner too (`POST /journeys/{id}/stages/{stage}/route`).
39. **The way there and back only where a journey starts and ends.** A
    stage's route page (website and app) no longer offers its own way there
    and back: the journey has it, from home before the first stage and home
    after the last (24).
40. **A journey's map in the app.** «Karte der Etappentour» shows all stages
    in their colours (those of the website), with the layer menu; below,
    the stages, each opening as a route.
41. **Reporting a bug.** A button in the website's header (until
    2026-10-02 a tab at its right edge, over the page) and a tab at the
    right edge of every app screen, for signed-in people: a description, what is open (the address without
    a share token, or the app's screen and item), the version and a
    screenshot (taken before the dialog opens; maps included on the
    website, empty in the app, where MapLibre draws natively) go to
    `POST /bug-reports`. The API opens an issue in the private repository
    with `ALVYO_GITHUB_TOKEN` (the description in a fence, so it mentions
    no one); the screenshot is committed to that repository
    (`screenshots/YYYY-MM/<report id>.png`) and shown in the issue (since
    2026-10-15; before, it stayed in the database for moderators; those
    were moved there and migration 0039 drops their columns). Five in a
    burst, then one every three hours per person.
42. **The app's map layers.** The website's overlays in the app's «Karten»:
    hiking trails, SchweizMobil, slopes over 30°, wildlife rest areas,
    hunting reserves, relief, huts, hotels and campsites, along the way;
    remembered on the phone.
43. **The app's base maps.** National map, grey and aerial photo
    (SWISSIMAGE). The website's vector «Basiskarte» is left out: switching
    to it would reload the style and every screen's own layers.
45. **Opening what was sent.** The app is signed with a free Apple ID,
    which cannot use universal links (Associated Domains need a paid
    developer account). So a shared link opens the website, and there, on
    an iPhone or iPad, «In der App öffnen» opens the route, journey or
    collection in the app (`alvyo://open/routes/{id}?t=…`), also when the
    app was closed or not signed in yet; the link's share token goes along
    with every call for that item. Universal links once there is a paid
    account.
46. **Inviting in the app.** The share sheet of routes and journeys also
    for collections: the link, and people invited by name or e-mail
    address as viewers or editors.
47. **Along the way on a stage's map.** What lies along a route or stage
    (34) is drawn on its map with the kinds' icons, on the website and in
    the app, named on a tap; all of it, as in the list (since 2026-10-15,
    feedback issue 1: the kinds switched off in the layer menu hid points
    the list showed; they now only filter the places around).
48. **Along the way, in more kinds.** Besides summits, viewpoints,
    waterfalls, drinking water and shelters: fire places, picnic spots,
    restaurants and cafés (all of them, named ones), toilets and cable car
    stations, from OpenStreetMap (`import-places.sh`; run the import after
    the release). Under «Unterwegs» in the layer menu each kind is switched
    on and off, remembered.
49. **Changing a route in the app.** «Auf der Karte ändern» in a route's
    menu opens the planner with its points: a new start, destination or
    points between; the legs not touched are kept as they are (also those
    dragged onto another path on the website), saved over the version seen.
50. **Closures and shooting on request.** A line with how many there are
    («2 anzeigen», highlighted with «gilt jetzt» or «gilt an einem geplanten
    Tag»); the list in a popup (website) or sheet (app). The closures have
    no areas of their own in our data, so no map layer.
51. **Protected areas on request.** As 50; their areas are on the map as
    the overlays «Wildruhezonen» and «Eidg. Jagdbanngebiete».
52. **Weather with icons.** MeteoSwiss's pictogram number of the day
    (`jp2000d0`), as our own icons (MeteoSwiss's graphics may not be
    reused), eleven for the 42 symbols, named with MeteoSwiss's words in
    the four languages.
53. **Weather for any date.** Besides the next days, any date up to a year
    ahead. Beyond the forecast: MeteoSwiss's climate normals 1991–2020 of
    the station most like the place (temperatures carried to its height,
    6.5 °C per 1000 m) and of the nearest precipitation station: «Üblich im
    Oktober: 3–11 °C, an 10 von 31 Tagen Regen, 102 mm im Monat»; on a
    journey for stages planned later. The normals are part of the API
    (`api/internal/weather/normals/`).
54. **Journeys planned ahead, with reminders.** By e-mail to the owner and
    the people along with an account, after 8:00: three weeks before the
    first planned stage «Übernachtungen buchen» (only while nights before
    the last stage are not booked, listed), two days before the weather,
    the day before the start; each once per start date. On the phone the
    same as local notifications (9:00 and 18:00). Each person turns theirs
    off on the journey («Erinnerungen», `PUT /journeys/{id}/reminders`).
55. **People on stages and journeys.** «Wer kommt mit» on a journey: the
    owner adds people by name or e-mail address (someone without access is
    invited as a viewer; a role they have is kept) and removes them; owner
    and editors choose their stages. Shown on the journey and on each stage
    («Mit Anna, Beat»), to the owner and those it is shared with, never to
    the public; addresses to the owner only (`/journeys/{id}/people`).
56. **Icons along the way.** Each kind of 48 has its icon (a white shape on
    a disc of its colour, the same on the website and in the app), on the
    map, in the layer menu and in a route's list.
57. **One's pace chosen.** «Dein Tempo» on the account page and in the
    app's profile: hiking times as 60–200 % of the signposts'
    (`speed_factor`), shown so on the website and in the app (in the app
    before only in planning and while hiking).
58. **A route's page in tabs.** After a proposal for the sidebar: one
    main action («Bearbeiten»), beside it GPX, «Merken» (the like, the same
    as the one with the comments) and «Teilen» (the address, with the share
    token of an unlisted route; the phone's share sheet where there is one);
    the sheet to print, collections, versions and deleting in a «⋯» menu.
    The four numbers in one strip, the way back in the time's tooltip. Below,
    tabs that stay at the top while the sidebar scrolls: «Übersicht»
    (description, closures and protected areas, the weather for today,
    tomorrow or a date picked, and «Wegbeschaffenheit»: trail network,
    surface and kind of way, a bar only where there is more than one kind,
    the three largest in per cent, the kilometres behind «Details»; a route
    off marked trails all the way says so in a warning), «Unterwegs» with
    its count and a chip per kind, «Anreise» (a connection per line, the
    chosen one with its legs, three and then «Weitere Verbindungen») and
    «Fotos» with likes and comments. The sidebar is 384 px wide. The app's
    route screen has the same numbers and tabs below «Wanderung starten»,
    its tab bar pinned while the panel scrolls. Journeys the same way
    (2026-10-02): GPX, «Merken» and «Teilen» at the top, collections, the
    app and deleting in «⋯», the numbers and the progress, then «Etappen»
    (first: what is worked on most), «Übersicht» (weather, closures and
    areas, «Wer kommt mit», reminders), «Anreise», «Fotos» and, for the
    owner, «Teilen» (visibility, link, invitations); journeys have no
    trail conditions (their totals carry none). In the app «Etappen»,
    «Übersicht», «Anreise» and «Fotos» below «Alle Etappen offline
    speichern» (sharing stays in the menu).

59. **Traces and metrics to the observability stack.** API and web are
    instrumented with OpenTelemetry. Traces go by OTLP to the collector on
    their node (in production the DaemonSet's host port 4318 in
    `OTEL_EXPORTER_OTLP_ENDPOINT`; without an endpoint
    nothing is sent); metrics are served for Prometheus on a port of their
    own (9464, `ALVYO_METRICS_LISTEN` and `METRICS_PORT`, not behind the
    ingress) and scraped through a ServiceMonitor. API: a span per
    request named after its operation (`GET /api/v1/routes/{id}`), the
    database queries (otelpgx) and outgoing requests (GraphHopper,
    geo.admin, MeteoSwiss, OJP) under it; request, database pool and Go
    runtime metrics. Web: SvelteKit's spans (handle, load, actions), the
    trace continued into the API, request durations per route. Logs stay
    on stderr, where the collector already reads every container's into
    VictoriaLogs, now with `trace_id` and `span_id`. The collector sends
    traces to Tempo (a week kept, span metrics and the service graph
    to Prometheus); Grafana links a trace to its log lines and metrics, and
    a log line to its trace.
60. **Friends.** Mutual: one asks (an e-mail with the «new follower»
    setting), the other accepts or declines, either ends it; blocking ends
    it too. «Freunde» (website header with the requests waiting, the app's
    profile): a search for public profiles by username or name, the
    requests both ways, one's friends, and one's invite link (renewable):
    whoever opens it and agrees becomes a friend at once. A profile is
    public (default) or private («Öffentliches Profil» in the account and
    the app's profile): a private one is not found and is seen by friends
    only; follows stay as they were. Friends are offered when sharing and
    in «Wer kommt mit».
61. **Hiked.** «Gewandert» on a route or journey one can see marks it as
    hiked on a day (today unless chosen), for oneself; one's recorded
    hikes and the routes they were hiked on count without a mark, and a
    journey for its owner and editors once none of its stages is left
    planned (`route_done_on`, `journey_done_on` in the database). «Meine
    Routen», «Etappentouren» and the app's lists filter «Alle / Geplant /
    Gewandert» and show the day; so does the map of one's hikes.

62. **Statistics with Google Analytics.** The Google tag (G-0S92XGEV7Y)
    once per page in `app.html`, on alvyo.tellbow.ch only (not in
    development and tests). Consent Mode: until a visitor accepts the
    banner («Akzeptieren / Ablehnen», remembered in the browser, changeable
    under «Über» → «Statistik»), Google sets no cookies and gets cookieless
    pings only. Page views are sent by the site itself on every navigation
    (`#lib/analytics`): the address without query and fragment (share
    tokens, password resets) and with the token of live location and
    invitation links masked, the route's pattern as title (not the titles
    of tours). The privacy text says so instead of «no tracking».
63. **A point along the way on the map.** On the website, the pointer on a
    line of «Unterwegs» rings its point (or the points it groups) on the
    route's map, which moves there when none is in view; in the app a tap
    on the line does the same.
64. **The app catches up with the website.** «Wegbeschaffenheit» on a
    route's «Übersicht» (trail network, surface and way type in per cent,
    the kilometres under «Details») and «Kein offizieller Wanderweg» when
    the whole route runs off marked trails; «Fotos» says how many there
    are; «Alle / Geplant / Gewandert» on «Karte meiner Touren»; a friend's
    invite link opens in the app («In der App öffnen» on the invite page,
    `alvyo://open/friends/invite/{token}`) and makes friends there.
65. **How far one gets («Wie weit komme ich?»).** «Planen» has a third tab,
    «Reichweite» (`/plan/reach`): from a point on the map or a place found
    by name, the areas reached on foot within 2 h (green), 4 h (yellow) and
    8 h (red) at one's pace, on hiking or alpine ways (`POST
    /routing/reach`, logged in, six per minute, two at a time). GraphHopper's
    isochrones over two profiles of their own, `hike_time` and
    `alpine_time`, timed by slope like the Swiss formula (median 2.7 %
    short of the official times of 28 stages, docs/hiking-time.md); the
    graph has elevation for it (30 m terrain tiles, skadi). An area is the
    outline around what is reached, lakes and pathless slopes inside
    included: the page says «ungefähr». 8 hours take about 2 s on the dev
    machine, 7 s in production. In the app: «Wie weit komme ich?» (the radar icon above «Meine
    Routen»), from a tap on the map, a place or where one is, the map fitted
    to the 8-hour area. From there to planning (issue 13): a click or tap
    inside the areas says within how many hours and offers «Hierhin
    planen» (and «Von hier aus neu»; outside the areas a click starts
    anew): the planner opens with the start (its name if found by search)
    and that point, the same profile; in the app with «Zurück zum Start» as
    «Rundtour». On the website as `/plan?from=lon,lat&to=lon,lat&profile=…`.

66. **A shared collection shares its items.** A collection shared by link
    or invitation showed «Noch leer»: its routes and journeys were private,
    and a collection never granted access to its items (issue 17). Now an
    item its owner added is shared with whoever sees the collection, in
    their role there (viewer or editor; the collection's owner as editor;
    by link or as public always viewer). Owner rights (visibility, share
    link, invitations, deleting) stay with the item's owner, and the higher
    of a direct invitation and the collection's role counts. Items someone
    added who does not own them stay as they are, so an editor cannot pass
    on a route only shared with them. Stage routes follow their journey.
    Invited people need nothing more; whoever sees a public or unlisted
    collection without an invitation opens its items with the collection
    as share token (`?t=c.{id}`, `.{token}` added when unlisted), on the
    website and in the app (where a journey's stages now also carry the
    token the journey was opened with). Taking an item out of the
    collection takes the access away. The collection says how many items
    the viewer cannot see («Private Einträge, die du nicht sehen kannst:
    3»); «Noch leer» only when there are none.

67. **Rain radar and forecast on the map** (issue 15). «Regen (Radar und
    Prognose)» under «Karten», on the website and in the app, like SRF
    Meteo's «Niederschlagsradar»: a card with play and a slider, from the
    last hour measured by MeteoSwiss's radar (every 5 minutes, 1 km, about
    10 minutes late; open data `ogd-radar-precip`, ODIM HDF5) to the next 12
    hours of the ICON-CH1 forecast («Modellprognose», hourly, 1 km, a run
    every 3 hours; `ogd-forecasting-icon-ch1`, GRIB2 on ICON's own grid,
    precipitation summed since the run started); it starts at the newest
    radar picture, shows the time (a forecast hour as «10:00–11:00») and a
    legend from «leicht» to «stark», © MeteoSchweiz (CC-BY). The job
    `weather-precip` (Python in the data-import image: h5py, GDAL, ecCodes,
    SciPy; the API is built without cgo and cannot read HDF5) runs every 5
    minutes, converts a forecast run once (the nearest model cell for each
    pixel) and keeps paletted Web Mercator PNGs (about 15–20 KB) in
    `precip_frames`; `GET /weather/precip` lists them, the pictures are
    cached for a day under their version. The app keeps one image source a
    picture and moves one layer between them (the iOS plugin cannot change
    an image source); without reception the last pictures stay.

68. **Recognising mountains with the camera** (issue 16; iPhone, also
    offline). «Berge erkennen» (the mountain icon on «Meine Routen»): the
    back camera's picture with the summits in sight named, their height and
    distance, and the skyline as a line. The pack (`GET /peaks/pack`, logged
    in, 8.6 MB): a height grid of Switzerland and about 50 km around it
    (5.0–11.5°E, 45.2–48.4°N, about 150 m cells from Mapterhorn's terrain
    tiles at zoom 9, rows as differences, gzipped) and the 11 183 named
    summits with a height; the API builds it in the background (7 s, 31 MB)
    and keeps it a week; the app downloads it once. On the phone: a summit is
    named when no terrain between rises above it (earth curvature and
    refraction counted; the first 300 m and the summit's own flanks left
    out, as the grid smooths them), up to 200 km, the highest first, at most
    30 without overlaps; about 0.5 s a place. Native Swift (PeakCamera.swift):
    the camera as a platform view, CoreMotion's attitude to true north 30
    times a second with the camera's field of view; one drags the drawn
    skyline onto the real one when the compass is off. The nearer ridges as
    fainter lines, like PeakFinder: along each ray a crest where visible
    terrain drops out of sight for at least 300 m or 15 % of its distance,
    joined to the next ray's crest at about the same distance and angle;
    rays and ridges from 300 m on (the grid cannot show closer terrain).
    Portrait only. Not on the website (Safari has no WebXR).

69. **The app's navigation tidied up** (the concept «Alvyo – UI aufräumen»
    from the project owner). Each tab answers one question: **Entdecken**
    (where to?), **Planen** (how?), the record button (go!), **Touren**
    (what do I have?), **Profil**; tabs are built when first shown. Every
    tab has a large title and at most one action with a word; one tour card
    for routes, journeys and others' items, the kind above the title
    («ETAPPENTOUR · 6 ETAPPEN» in the accent colour, «ROUTE · GETEILT VON
    …»), the figures as distance · time · ascent · difficulty, a journey's
    stages as a bar «2 / 6»; empty lists name the next step («Tour
    planen», «Aufzeichnen», «Freunde»). Entdecken: a search for places and
    summits (opens the discover map there), «Wie weit komme ich?» (to
    Planen › Reichweite) and «Gipfel anschauen» (68), three of «Von Leuten,
    denen du folgst» («Alle» for the feed; the tab «Neuigkeiten» is gone),
    three public tours «In deiner Nähe» (about 15 km around), «Karte» for
    the discover map. Planen: «Tagestour» (the route planner with «+
    Zwischenziel» before the destination and «Rundtour» back to the start,
    saved with the way back), «Mehrtägig» (the journey planner), «Reichweite»
    (the areas of 2, 4 and 8 hours as before, with the layer menu of the
    other maps; «Zurück zum Start», off by default: the areas from which one is back within them, out and back
    timed each in its own direction, uphill slower than down: `POST
    /routing/reach` with `back` asks GraphHopper for its shortest path
    trees from and to the start, keeps the paths to the nodes whose two
    times fit, rasterises them in cells of about 230 m and has PostGIS
    outline the cells, gaps up to 600 m between paths closed and holes
    under 1 km² filled (a lake stays out); from Sargans about a third of the area one way,
    0.6 s on the dev machine; the website keeps one way); the three share
    one panel over the map, pulled up and down alike; «Importieren»: a GPX, KML, TCX or FIT
    file (file_selector, any file: iOS knows no GPX type) becomes a private
    route, opened at once, or hikes from the Apple Watch. Touren: «Geplant»,
    «Gewandert», «Sammlungen»; «Alle», «Routen», «Etappentouren», «Geteilt»;
    «Karte» for the map of one's tours. Aufzeichnen: a close button, «Einer
    Tour folgen (optional)» among one's tours not hiked and those shared
    (followed on the route's page, as «Los»), «Aufzeichnung starten».
    Profil: one's card, «Freunde», «Verbundene Geräte» (the Apple Watch:
    «Neue Wanderungen automatisch importieren» when the app opens or comes
    back, at most every 10 minutes, those since switched on; «Wanderungen
    auswählen und importieren»), «Einstellungen» (each with its value, chosen
    in a sheet; the e-mails under «Benachrichtigungen»), «Konto». The
    session is checked when the app opens (it was with the routes list).

70. **The official routes** (issue 14). The hiking routes of Wanderland
    Schweiz (ASTRA and SchweizMobil, `ch.astra.wanderland`, open data that
    names its source): 7 national, 70 regional, 274 local and 89 barrier-free
    routes, public in «Entdecken» as routes (one stage) and journeys (several)
    of the account «wanderland» («Wanderland Schweiz», which cannot log in).
    The job `wanderland-import` (monthly) loads the GeoPackage into
    `wanderland_routes`, `wanderland_stages` and `wanderland_transport` in
    one transaction; the API syncs within 6 hours of a newer import
    (`internal/official`): new routes are created, changed ones updated in
    place (likes, collections and hiked marks stay), gone ones deleted, and
    an import of fewer than 100 routes is refused. Wanderland keeps a stage
    as pieces; without loops round a station (under 500 m) and branches off
    a junction (under 300 m) the line walks every piece once, or else is the
    longest path between two ends; all 976 stages within 20 % of the
    official length (median 98.5 %) and time (99.6 %). Where a stage rides a
    boat, a bus or a cable car (12 stages, e.g. Luzern – Altdorf across the
    lake), the parts walked become stages of their own with «Umsteigen
    davor». Times, SAC grades and heights are computed as for every route.
    A route's or journey's page names it («Nationale Route 1 · auf
    SchweizMobil ↗», the link in the page's language) and the source
    instead of the owner, on the website and in the app; «Entdecken» filters
    «Herkunft» (official, people's, both) and names official routes in its
    list. «Als eigene Route bearbeiten» / «Als eigene Etappentour
    bearbeiten» (`POST /routes/{id}/copy`, `/journeys/{id}/copy`) gives
    whoever is logged in a private copy of any route or journey they can see
    (not of others' recorded hikes, whose ends are hidden), opened in the
    planner; a journey's copy keeps its stages, routes and transfers, not
    dates, marks, notes or places to stay. On the website it is the main
    action for those who may not change the item, in the app in its «⋯» menu.

71. **AI assistants and the command line** (issue 28; read-only,
    personal access tokens rather than OAuth, the CLI also on its own).
    «Zugriffstoken» under «Konto» on the website and in the app: named,
    with when they were made and last used (within the hour), at most 20,
    revoked at once; the token (`alvyo_pat_…`) is shown once, only its
    SHA-256 is kept, and a password reset removes them all. With a token
    the API answers GET requests only (others 403, a wrong or revoked
    token 401), at most 60 at once and one a second after; the costly
    ones count against the user's limits as from the website. The MCP
    endpoint `/api/v1/mcp` (streamable HTTP, stateless, the official Go
    SDK) takes only access tokens and offers nine tools that only read:
    `search_places`, `plan_route` (from, via, to by name or «lat,lon»;
    distance, ascent, Swiss hiking time also at one's pace, SAC grade, GPX
    on request; places more than 40 km apart are refused as likely found
    by mistake), `reach`, `route_conditions` (weather, closures and
    shooting, protected areas of a saved or a planned route), `discover`
    (public and official routes around a place), `my_routes`,
    `my_journeys`, `get_route`, `get_journey` (one's own, shared, public,
    or unlisted with the token). Each answers with a text and the same as
    JSON. `alvyo-cli` (`api/cmd/alvyo-cli`) calls these tools:
    `alvyo-cli route plan Sargans Weisstannen --gpx`, `alvyo-cli discover
    --near Thun --official`, `alvyo-cli routes`, as text or `--json`;
    `alvyo-cli mcp` serves them over stdio for assistants that start a
    local program (Claude Desktop). Each release attaches it for Linux,
    macOS and Windows. Setting up: [mcp.md](mcp.md).

72. **Licences and credits, ready to publish** (issue 25). The terms of
    every data source and service checked and written down with links
    ([licensing.md](licensing.md)); NOTICE lists all of them and the
    third-party code. Credits wherever the data shows: on the website's
    maps OpenStreetMap linked to its copyright page, ASTRA and BAFU with
    their overlays, the reach areas with Mapzen's terrain, the print sheet
    with openstreetmap.org/copyright; in the app a credit line in every
    map's upper left corner («© swisstopo · © OpenStreetMap», the offices
    of the overlays that are on; a tap lists all sources) and on the peak
    camera (Mapterhorn, OpenStreetMap). The About page lists every source
    with its terms, links NOTICE of the running version, names the
    operator (`PUBLIC_OPERATOR_NAME`, `PUBLIC_OPERATOR_ADDRESS`) and has a
    fuller privacy text (own servers in Switzerland, e-mail through
    Infomaniak, sign-in providers, the app's location and Apple Health,
    one's rights); «Über Alvyo» in the app's profile has the sources, the
    source code, NOTICE, the license page of all packages and fonts, and
    the privacy text and operator on the website, which the login screen
    links too. Bug reports say they become public issues. The Komoot import
    is gone: Komoot's terms forbid exporting tours other than with its own
    export and passing on the password; the import page says to upload
    Komoot's GPX export instead. Contributions come under a CLA (CLA.md,
    CONTRIBUTING.md), so the app can go into the App Store; `make licenses`
    checks the licenses of all packages; `.claude/rules/licensing.md`
    asks for the terms before a new API, data source or package.

73. **The app on the iPad.** At 820 points wide and more (any iPad in full
    screen but the mini upright, a phone turned sideways) the places are in
    a rail on the left instead of the floating bar, the record button among
    them; a route, a journey (with its stages' map), Planen's three modes,
    the discover map, a collection's map and the way there have their panel
    on the left, 375 wide, and the map beside it at full height; lists and
    forms are at most 720 wide in the middle. Upright and on its side, in
    Split View narrower than that as on a phone; turning keeps the tabs and
    the maps. App Store screenshots for 13-inch iPads come from the iPad Pro
    13-inch simulator (2064 × 2752).

### Open

14 was added on 2026-09-24 from a survey of Komoot, AllTrails,
Outdooractive, SchweizMobil, the swisstopo app and others, and waits for
Garmin. 44 is from the project owner on 2026-09-29.

#### 72. The Android app (issue 8, started)

The app on Android as on iOS, its APK with every GitHub Release, later in
the Play Store; Google Analytics as for iOS (issue 9) comes after.

Done (2026-10-12): the app builds and runs (minimum Android 8, the iOS
icon as adaptive and themed icon); recording and navigation with the
screen locked through a foreground service with a notification (no
background location); spoken turns with Android's text-to-speech, other
audio turned down; off-route warnings and journey reminders as
notifications in their own channels, asked for on Android 13 and later;
`alvyo://open/…` links, and app links: the website's addresses of a route,
journey or collection and invite links open in the app (verified against
`/.well-known/assetlinks.json` with the release key's fingerprint, also
under /en/, /fr/, /it/); offline maps, the peak pack and the login kept out
of backups; texts that named the iPhone name the phone. CI builds the
APK; the release workflow signs it with the release key (secrets
`ANDROID_KEYSTORE`, `ANDROID_KEYSTORE_PASSWORD`, app/README.md) and adds
it to the GitHub Release. The integration tests offline, navigate and
journey pass on the emulator. Found on the way: the login screen could
overwrite a server typed before the last one was read, and on Android a
camera move cut short by the next position skipped the rest of it
(progress, warning, spoken turn).

Open: «Berge erkennen» (a CameraX view and the rotation sensor) and the
watch import through Health Connect, hidden on Android until then; the
Play Store (developer account, listing, data
safety form, an AAB); the manual tests on a real phone
([manual-tests.md](manual-tests.md)).

#### 44. 3D in the app (blocked)

The terrain in 3D as on the website (36). MapLibre Native for iOS (6.29,
under the Flutter plugin) has hillshading but no 3D terrain. Possible: the
website's 3D map in a web view, or waiting for MapLibre Native.

#### 14. Routes to Garmin devices (deferred)

Komoot put sending routes to Garmin behind its paywall in 2025. Garmin's
Courses API needs an application to the Garmin Connect Developer Program
(company details, approval not guaranteed); the project owner applies
first. Until then routes reach a Garmin through the GPX export and Garmin
Connect's course import.

## Backlog

- Community and moderation: moderators opening unlisted reported items;
  shadow-ban.
- Journeys: cancelled trains and buses are not shown in connections (OJP).
- Operations: backups are kept on the cluster only; an off-site copy is
  missing.
- Texts: the French and Italian texts to be reviewed by a native speaker.
- Logo: the Λ of the Alvyo mock-up, drawn as a vector for the web and the
  app icon; a final one from a designer.
- Design: the mock-up's moods, logbook and «send to app».
- M4: the Swiss Map Raster 25 (1:25 000) served from own tiles instead of
  swisstopo's WMTS (20–40 GB of tiles).

## Not tested on devices

What only a phone or a real hike can show, and what is still open there:
[manual-tests.md](manual-tests.md).
