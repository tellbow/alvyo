# Plan

What Alvyo is for, what is done and what comes next. Keep it current:
when a requirement is done or changes, update this file in the same commit.
Status: 2026-09-28.

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
| M3 | iOS app: offline maps, navigation, recording, Apple Watch import, spoken turns, journeys, planning | done up to 0.9.0; open items in the backlog |
| M4 | Extras: weather, points of interest, PDF stage sheets, 3D, closures | open |

## Releases

A `v*` tag builds the images; Flux deploys them
([operations.md](operations.md)). Production: https://alvyo.tellbow.ch
(https://odysgeh.tellbow.ch redirects there).

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

## Requirements

From the project owner, numbered in the order given: 1–5 added on
2026-09-23, 6–11 on 2026-09-24, 15–18 on 2026-09-26, 19–20 on 2026-09-27,
21–27 on 2026-09-28.

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
    collections; in the profile the map of one's tours, the e-mail
    notifications, the contacts for shared hikes, blocked people and
    deleting the account; signing up and a forgotten password open the
    website. Left to the website: moderation, imports (files, Komoot),
    passkeys and sign-in providers, planning a route again on its map.
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

### Open

Added on 2026-09-24 from a survey of Komoot, AllTrails, Outdooractive,
SchweizMobil, the swisstopo app and others. 14 waits for Garmin.

#### 14. Routes to Garmin devices (deferred)

Komoot put sending routes to Garmin behind its paywall in 2025. Garmin's
Courses API needs an application to the Garmin Connect Developer Program
(company details, approval not guaranteed); the project owner applies
first. Until then routes reach a Garmin through the GPX export and Garmin
Connect's course import.

## Backlog

- Community and moderation: moderators opening unlisted reported items;
  shadow-ban.
- Routes: revisions; privacy zones (start and end of recorded hikes hidden);
  a border buffer for routes near and across the border; the routing gap at
  Chamanna Jenatsch.
- Journeys: cancelled trains and buses are not shown in connections (OJP).
- Operations: backups are kept on the cluster only; an off-site copy is
  missing.
- Texts: the French and Italian texts to be reviewed by a native speaker.
- Logo: the Λ of the Alvyo mock-up, drawn as a vector for the web and the
  app icon; a final one from a designer.
- Design: the mock-up's moods, logbook and «send to app».
- M4: MeteoSwiss weather, highlights and points of interest, PDF stage sheets,
  3D terrain, closures, self-hosted Swiss Map Raster 25, full «how to get
  there» by public transport.

## Not tested on devices

What only a phone or a real hike can show, and what is still open there:
[manual-tests.md](manual-tests.md).
