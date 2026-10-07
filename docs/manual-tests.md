# Manual tests

What automated tests cannot show. Tick off with the date and the device; note
anything odd. What the simulator could show was checked there with scripted
runs against the dev stack (the notes); the rest needs a phone or a hike.
Since 2026-10-01 the simulator runs also tap, swipe and type for real (idb,
`brew install facebook/fb/idb-companion` and `pip install fb-idb`): native
dialogs, the map, the photo picker and the share sheet; the website was
checked in Playwright's Chromium, Firefox and WebKit.

## App on the iPhone (release build)

Checked so far only in the simulator, with made-up or simulated positions
(`app/integration_test/`):

- [ ] **Recording with the screen locked** for a whole hike: the track has no
      gaps, and the battery use per hour is acceptable.
- [ ] **Off-route warning while locked**: the notification arrives, with sound
      or vibration. The notification permission is asked on the first hike.
- [ ] **No false alarms**: with real GPS jitter, in forests and on switchbacks,
      no warning while on the path (thresholds: 2 positions over 50 m, back
      under 30 m).
- [x] **Loops**: starting at the trailhead says nothing about arriving; the
      progress keeps going forward, «Ziel erreicht» at the end. Also a loop
      shorter than 1.5 km: nothing at the start, «Ziel erreicht» at the end.
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): made-up positions on a
      3.1 km and a 1.2 km loop: nothing said or shown about arriving at the
      start, the walked distance only grows, «Ziel erreicht» once at the end.
- [ ] **Location switched off mid-hike** (Control Centre or Settings): the
      banner says «Warte auf GPS …» until positions come again.
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): the banner shows on the
      error geolocator reports and goes with the next position; still to see
      on a phone: that switching it off in Control Centre gives that error.
- [x] **Logged out elsewhere** (or the session expired): opening the app shows
      the login, not «Server nicht erreichbar».
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): session ended on the
      server: the app opens on the login.
- [ ] **Remaining time** compared with the time actually needed, at the pace set
      in the account.
      2026-10-02: the pace is chosen on the account page or in the app's
      profile («Dein Tempo», 57); the app shows hiking times at it like the
      website (it ignored it before).
- [ ] **Spoken turns** on a planned route, phone in the pocket with the screen
      locked: «In 100 Metern links abbiegen» about 100 m before a junction and
      «Links abbiegen» about 20 m before it, then «Ziel erreicht». Heard over
      music (turned down meanwhile, back to full volume half a second after
      each prompt) and with the silent switch on; the voice
      (Swiss if installed, else German) and the timing at walking speed are
      right. Only simulated so far: the prompts and the iOS voice channel,
      not listened to.
- [ ] **Turns that are there**: every announced turn is a real junction, none
      is missing where the route leaves the main path; in villages (sidewalks,
      crossings) not too many. The turns are GraphHopper's for the OSM paths,
      checked on synthetic lines only (`api/internal/routing/turns_live_test.go`).
- [x] **Out-and-back route** (to a summit and back the same way): the turns on
      the way back are announced, the progress keeps growing. The U-turn
      itself may not be announced.
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): made-up positions, 3.3
      km there and back: the 7 turns on the way back are said (the U-turn
      too), the walked distance only grows.
- [x] **Voice button**: off stops the prompts for this hike (it is on again
      at the next start).
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): off stops the prompts;
      the next hike starts with the voice on.
- [ ] **Following on the map** at walking speed: the map glides to the position
      at zoom 15; panning stops following, the button brings it back. The
      map and the banner stay smooth with every new position.
      Simulator 2026-10-01 (iPhone 17 Pro, iOS 26.5): simulated walk at
      1.4 m/s through Sargans: the map follows, a real pan stops it and shows
      «Follow my position», the button brings it back. Still to see on a
      phone: whether it all feels smooth.
- [ ] **Offline map without reception** (airplane mode): the saved route and its
      map open, the position shows on it, the turns are announced (saved with
      the map; a map saved before this version has none offline).
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): with the server
      unreachable instead of airplane mode: the saved route opens on its map,
      the position shows, and the 3 saved turns are used.
- [x] **Saving an offline map** goes on after leaving the route screen, and a
      download broken off (reception lost, app in the background for long)
      continues where it stopped when saving again.
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): goes on after leaving
      the route screen; a download cut off after 98 kB continued from there
      (Range) when saved again.
- [x] **Saving an offline map in a hut's or station's Wi-Fi** that first shows
      a login page: the save fails and works once logged in to the Wi-Fi,
      without a broken map.
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): a login page instead of
      the map (faked): the save fails, nothing broken is kept, the next save
      works.
- [x] **iCloud backup**: offline maps are not in it (Settings → your name →
      iCloud → Manage storage → Backups: Alvyo stays small).
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): the offline maps folder
      carries com.apple.MobileBackup (excluded from backups).
- [x] **App stopped mid-hike** (swipe it away, open it again): the route offers
      «Wanderung fortsetzen» and the hike goes on.
      Simulator 2026-10-01 (iPhone 17 Pro, iOS 26.5): the app killed during a
      simulated walk (`simctl terminate`, as swiping it away does) and
      opened again: the route offers «Resume hike», the hike goes on (75 m
      walked before, 298 m after).
- [x] **Upload later**: finish a hike without reception; once online, it goes up
      when the route list loads and shows in «Meine Routen».
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): hike finished with the
      server unreachable; once online the route list uploaded it and shows it.
- [ ] **Apple Watch import** of real «Wandern» and «Gehen (im Freien)» workouts:
      the track and time are right; a paused workout (several route parts)
      comes out as one hike; a workout without GPS says so.
- [x] **Health access refused**: the watch screen explains where to allow it.
      Simulator 2026-10-01 (iPhone 17 Pro, iOS 26.5): «Don't Allow» in the
      Health sheet; the screen says where: Settings → Apps → Health → Data
      Access & Devices → Alvyo.
- [ ] **Journeys** with more stages (a real multi-week one): «Save all stages
      offline» with a mobile connection, leaving the screen meanwhile; the
      journey and every stage open in airplane mode. Only tried with two
      stages on the local server.
      Simulator 2026-10-01 (iPhone 17 Pro, iOS 26.5): eight stages saved
      while away from the screen (151 s on the local server); the journey and
      all eight open with the server unreachable. Still to see on a phone: a
      mobile connection and airplane mode.
- [ ] **Free Apple ID expiry**: after 7 days the app no longer starts;
      `flutter run --release` renews it.

- [x] **Two accounts on one phone**: record a hike offline, log out, log in
      as someone else: the hike is not uploaded to them, nor resumed; back
      in the first account it uploads.
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): another account's login
      does not upload the hike; back in the hiker's account it uploads.
- [x] **Starting a hike on another route** while one is recorded asks
      first; «Abbrechen» leaves the running hike as it was.
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): asked; «Abbrechen» kept
      the hike and its positions.
- [x] **A stage ticked off**: after hiking a stage's route, «Etappe als
      gewandert markieren» in the message marks it (online); in the journey
      the check next to a stage does the same and back.
      Simulator 2026-09-29 (iPhone 17 Pro, iOS 26.5): a stage's route hiked
      with the simulator's location; the message's action marked the stage;
      the check in the journey marks it and back.

- [ ] **A shared hike on a real hike** (production, real e-mail): the contact
      gets the link, follows the position (with dead spots in a valley),
      «Später» works; ended without a connection, the end reaches the server
      once back online and nobody is alerted. An overdue alert (set the end
      a few minutes ahead) reaches contact and hiker, and the all-clear
      after «Später».
- [x] **A shared hike with reception that stalls** (a weak signal, not none):
      positions go out again once it is back, and «Beenden» returns within
      about 10 s.
      Simulator 2026-10-01 (iPhone 17 Pro, iOS 26.5): the app's sender and
      outbox behind a proxy that takes requests and never answers: the send
      gives up after 30 s and keeps the 5 positions, the next one once back
      sends them all; ending while stalled returns after 10.0 s, and the end
      reaches the server once back.
- [x] **Alvyo look in light and dark** (Settings → Display, and «Automatic» at
      dusk): the bar at the bottom, the record button (opens the hike in
      progress, else the hint), cards, fonts and the map screens readable in
      both; the new icon on the home screen.
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): screenshots of the
      lists, a route with photos and comments, a journey, a stage, the feed
      and the profile, in light and dark (switched in the profile).
- [x] **Huts on the map**: the layer button on the route, navigation and
      planning maps switches «Hütten» and «Hotels und Campingplätze», the
      choice holds on the next screen and after a restart; a tap on a dot
      opens its sheet, not the thing under it; offline nothing breaks.
      Simulator 2026-10-01 (iPhone 17 Pro, iOS 26.5): a real tap on the
      Glecksteinhütte in the planner opens its sheet and adds no point, «Add
      as route point» adds it, a tap beside it adds a point; offline, moving
      and tapping the map and switching layers raise no error.
- [x] **Route planen** on the phone: tapping the map adds a point, a hut's
      «Als Routenpunkt hinzufügen» too; the line and the dots follow as
      legs arrive; the sheet drags well over the map and the search results
      stay above the keyboard; the saved route opens, saves offline and
      navigates; the time at one's pace matches the website.
      Simulator 2026-10-01 (iPhone 17 Pro, iOS 26.5): real taps and typing;
      the results end above the keyboard, the sheet drags from 596 up to 272
      and down to 785 pt; Sargans → Weisstannen saved and opened, 4 h 20 min
      as on the website (at the default pace; see «Remaining time»).
- [x] **Etappentour planen** on the phone: the map at 40 % with the panel
      usable while typing (a decimal comma on the Swiss keyboard); the days
      in their colours, the other ways grey and a tap on one chooses it;
      «Ab hier weiter auf Weg N»; the created journey opens.
      Simulator 2026-10-01 (iPhone 17 Pro, iOS 26.5): the map 350 of 874 pt;
      «7,5» typed for real is read as 7.5 h («Not possible with at most 7,5 h
      a day: it takes at least 6 days»); a real tap on a grey way chooses it;
      «go on along way 1» and the created journey open.
- [x] **The most per day** in «Etappentour planen» (e.g. Thun → Zermatt in
      three days at most 8 h): no plan with a longer day, the message names
      the fewest days that fit and «In N Tagen planen» plans with them; with
      several ways, those that do not fit are left out.
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): Thun → Zermatt, 3 days,
      at most 8 h: «mindestens 6 Tage», and «In 6 Tagen planen» plans 6 days
      (129.2 km).
- [x] **Löschen** from the menu of a saved route and of a journey saved
      offline: asked first, back in the list without it, and the offline
      maps gone (storage in the iPhone settings).
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): a route and a journey
      saved offline: «Abbrechen» keeps them, «Löschen» removes them and their
      offline maps.
- [x] **Entdecken**: starts at one's position when location is already
      allowed and never asks for it; lines in colour, redrawn after moving
      the map or a filter; the offline message in airplane mode; another
      account's public route saves offline, is hiked and the hike uploads.
      Simulator 2026-10-01 (iPhone 17 Pro, iOS 26.5): opens at the simulated
      position in Sargans without asking; the list follows a real pan and the
      hiking time filter; another account's public route saved offline,
      hiked with the simulator's location and uploaded. The offline message
      on 2026-09-28.

- [ ] **Photos from the phone**: «Foto aufnehmen» asks for the camera once
      and adds the photo; several from the library go up one after the
      other (HEIC too); photos taken along the route show on the website's
      map. The large view swipes, zooms and deletes.
      Simulator 2026-10-01 (iPhone 17 Pro, iOS 26.5): a JPEG and a HEIC with
      positions picked together in the library: both go up and show as pins
      on the website's map; the large view swipes («2 / 2») and deletes
      («Really delete?»). Still on a phone: the camera and zooming.
- [ ] **Sharing from the phone**: «Link senden …» opens the share sheet
      (Messages, WhatsApp, Mail) with the link, which opens the route or
      journey; «GPX teilen …» saves to Files and imports into another app
      (a journey as a ZIP of its stages).
      Simulator 2026-10-01 (iPhone 17 Pro, iOS 26.5): the share sheet has the
      link with a preview; the link opens the journey without an account;
      a route's GPX saved to Files (1128 points), a journey's as a ZIP. Its
      name lost the dash («SargansWeisstannen»): fixed 2026-10-02, and the
      share sheet shows the title. Still on a phone: Messages, WhatsApp,
      Mail and the import into another app.
- [ ] **Public transport on a stage**: the SBB links open the SBB app or
      sbb.ch with the stops and the day; «Verbindungen von hier zum Start»
      asks for the location only if not yet decided, finds the nearest stop
      and shows connections with platforms and delays.
      Simulator 2026-10-01 (iPhone 17 Pro, iOS 26.5): the link opens sbb.ch
      with «Sargans» and the stage's day; the location is asked once, the
      nearest stop is «Mels, Verrucano». The connections were not shown: the
      OJP key in `infra/.env.local-test` is refused (HTTP 403).
- [x] **Language and look chosen in the profile**: the whole app changes at
      once and keeps it after a restart; «Automatisch» follows the iPhone
      again (also its dark mode at dusk); e-mails come in the chosen
      language.
      Simulator 2026-10-01 (iPhone 17 Pro, iOS 26.5): French and dark at once
      and after a restart; «Automatique» follows the system's light and dark
      again; a share e-mail came in French.
- [ ] **From home and back** on a real journey: the homes in the profile,
      «Anreise» and «Heimreise» on the journey; leaving at 6:00 and
      arriving by 8:00 give the trains one would take (compared with the
      SBB app), the dashed line runs from the door to the start, and the
      GPX has only the stages.
- [ ] **Recording without a route** (the record button) on a real hike,
      with the screen locked: the track has no gaps; the app stopped by iOS
      and opened again, the record button goes on with the same hike;
      «Beenden» opens the new route «Wanderung, <date>». Offline at the
      end: the message says it goes up later, and it does once online.
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): made-up positions
      along «Sargans–Weisstannen»: the track grows on the map, 8.2 km
      uploaded and opened as a route.
- [ ] **Across the border** (after the first graph refresh in production
      with the neighbouring countries): a route from Martigny to Chamonix
      planned on the website, saved offline in the app and hiked or walked
      past the border: the national map shows the French side, turns are
      spoken there, and the recorded hike is accepted.
      Simulator 2026-10-01 (iPhone 17 Pro, iOS 26.5), local graph: Martigny –
      Col de Balme – Chamonix planned (34 km, 44 of 96 turns in France),
      saved offline, walked past the border: the map shows the French side,
      the turns go on, the hike uploads. Production not checked.
- [ ] **How to get there** (after a release): on a route, «Anreise» from
      «Anderer Ort …» (a station found by the search) and «Heimreise» to a
      home, on a day chosen: the connections match the SBB app, the chosen
      one is drawn on the map; the same on the website afterwards.
- [x] **Weather** (after a release): on a route high up, «Wetter» names
      forecast points at a similar height (a hut, not the valley village);
      the days after «Heute» fit on the screen; on a journey only the
      stages planned in the next days, and a planned day changed in the
      stage sheet shows its forecast on returning. Compared with the
      MeteoSwiss app for the same place and day.
      Simulator 2026-10-01 (iPhone 17 Pro, iOS 26.5): «Spitzmeilenhütte SAC,
      2087 m» for the high end; the days wrap on the screen; a stage 40 days
      out shows the climate normals (requirement 53), moved to the day after
      tomorrow in its sheet its forecast. Sargans as in the MeteoSwiss app:
      Fri 13.6–19.6 °C and 14–20 °C, 1.5 mm (0–5.2) in both.
- [x] **Map layers** (42, 43, 48, 56): in «Karten» the Luftbild and the grey
      national map replace the national map, the overlays (slopes, wildlife
      rest areas, relief …) lie above it and below huts and the route line,
      and both stay chosen on the next screen and after restarting the app.
      «Unterwegs» shows its icons from zoom 12, sharp (not blurry), a tap
      names them, and the kinds switched off stay off.
      Simulator 2026-10-01 (iPhone 17 Pro, iOS 26.5): Luftbild with slopes,
      below the trails, the line and the icons; kept in the planner and after
      a restart; «Unterwegs» none at zoom 11.5, 7 at 13, water switched off
      stays off; a real tap named «Feuerstelle Weisstannen Erlenbach».
- [x] **A route's points along the way on its map** (47): on a stage's route,
      the icons of what lies along it, above the line; tapping one names it.
      Simulator 2026-10-01 (iPhone 17 Pro, iOS 26.5): see «Map layers».
- [x] **A journey's map** (40): «Karte der Etappentour» shows all stages in
      their colours, the whole journey in view; a stage below opens it.
      Simulator 2026-09-29 (iPhone 17 Pro, iOS 26.5): two stages in their
      colours, both in view; the stage below opens its route.
- [x] **Adding and planning a stage** (38) and **changing a route on the map**
      (49), after a release: the new stage's planner starts where the stage
      before ends; a changed route keeps the legs not touched (also dragged
      ones from the website).
      Simulator 2026-10-01 (iPhone 17 Pro, iOS 26.5): the new stage's planner
      starts at the end of the stage before, and the saved stage there; with
      the destination replaced, the first leg and a leg dragged onto another
      path stay the same.
- [x] **Links into the app** (45): on the iPhone, a shared link opens the
      website; «In der App öffnen» there opens the route, journey or
      collection in the app, also an unlisted one (its link's token), also
      when the app was closed or not signed in yet (opened after signing in).
      Simulator 2026-10-01 (iPhone 17 Pro, iOS 26.5): from Safari, «Open in
      the app» opens another account's unlisted route; links to a route,
      journey and collection open with the app running, closed, and signed
      out (after signing in).
- [ ] **Reporting a bug from the app** (41): the tab at the right edge on
      every screen, not in the way of buttons; the screenshot shows the
      screen (the map itself stays empty: MapLibre draws it natively); the
      issue arrives on GitHub once `ALVYO_GITHUB_TOKEN` is set.
      Simulator 2026-10-01 (iPhone 17 Pro, iOS 26.5): the tab on every screen
      visited, clear of the buttons; the report reaches the server with the
      screen's screenshot. Still to see: the issue on GitHub (token).
- [x] **Reminders on the phone** (54): with a stage planned in a few days,
      the notifications «Übermorgen geht es los» and «Morgen geht es los»
      come at 18:00; turned off on the journey, they no longer come; for
      someone along, on their phone too.
      Simulator 2026-09-29 (iPhone 17 Pro, iOS 26.5): both scheduled for 18:00
      (pending notifications; not waited for); gone when turned off, back
      when on; scheduled for someone along too.

- [ ] **A journey's tabs on the phone** (58): «Etappen» first; ticking a
      stage off, adding one and «Alle Etappen offline speichern» as before;
      people and reminders on «Übersicht».
      Simulator 2026-10-02 (iPhone 17 Pro, iOS 26.5): the four tabs, the
      numbers and the profile on «Übersicht»; `journey_test.dart` passes.
- [ ] **A route's tabs on the phone** (58): the four numbers fit in one row
      on the smallest iPhone; «Wanderung starten» and the tab bar are reached
      without scrolling; the tab bar stays while the panel scrolls; switching
      tabs keeps what was loaded (photos, the way there).

- [ ] **Friends in the app** (60): the invite link from «Link senden» opens
      the website on the other phone and makes friends; requests and the
      private profile switch as on the website.
- [ ] **Hiked in the app** (61): «Als gewandert markieren» with the date
      picker; the lists' «Geplant / Gewandert»; a recorded hike counts.

## Web

- [ ] **Google Analytics** (62): after the release, the banner on the
      first visit (also on a phone, not covering the planner's buttons);
      GA's real-time report shows the visit, addresses without `?t=` and
      `/live/-`. In GA's data stream, «Page changes based on browser history
      events» is off (2026-10-05): the site sends its page views itself.
- [ ] **Telemetry on rk1** (59): after the release, Prometheus scrapes
      the api and web targets (up) with their request durations;
      VictoriaLogs lines of the API carry `trace_id`; the collector logs no
      export errors. In Grafana: a trace of alvyo-api in Tempo, «Logs for
      this span» shows its lines in VictoriaLogs, «Related metrics» the
      request rate and p95; a VictoriaLogs line of the API has a «Trace»
      link that opens it.
- [ ] **How far one gets on rk1** (65): after the new graph, «Reichweite»
      from a few starts (a station in a valley, a hut): the areas follow the
      valleys, 8 hours answer within about 10 s, the planner still routes.
      In the app on the iPhone: «Mein Standort» asks for the location once
      and starts there. Simulator 2026-10-05: from Sargans, filled areas,
      the map on the 8-hour area.
- [ ] **Invite link on the iPhone** (64): a friend's invite link opened in
      Safari offers «In der App öffnen»; the app shows who invites and
      «Freunde werden» makes friends. The app on the iPhone after the
      release, as it talks to production.
- [ ] **A shared collection on the iPhone** (66): the link of an unlisted
      collection with private routes and a private journey, opened in
      Safari and with «In der App öffnen»: its items open, also a stage of
      the journey with its weather and photos. Invited as editor, a route
      in it can be changed. After the release, as the app talks to
      production.
- [ ] **A route's page** (58) in Safari on the iPhone and the Mac and in
      Firefox: «Teilen» opens the share sheet on the iPhone and copies the
      link on the Mac; «Anderes Datum» opens the date picker; the «⋯» menu
      closes when tapping beside it; the tab bar stays while scrolling.
      Playwright 2026-10-02 (Chromium, 1440 px and 390 px, light and dark):
      the tabs, menu, numbers and cards as proposed.
- [ ] **Stage sheets** printed on paper and saved as PDF, from Safari on
      the iPhone and Mac and from Chrome and Firefox: one A4 page for a
      real stage (Etappe of a Via Alpina journey), the map sharp enough to
      read the trail, the grade badge and profile in colour, nothing cut
      off at the page break; in dark mode the sheet is light.
      2026-10-02: Sargans – Weisstannen with a day, a night and three
      connections fits one page in Chromium's PDF (`sheet.e2e.ts`; it took
      two before): «Unterwegs» groups a town's fountains and restaurants and
      runs in three columns on paper, the numbers, places and weather side
      by side. The map is drawn a zoom level deeper and sharp. Still to
      print from Safari and Firefox.
- [x] **Place search** with more names: villages, peaks, passes, huts, stops and
      addresses, also French and Italian names.
      2026-10-02, local: names just as searched come first, so «Zermatt»,
      «Grindelwald», «Sargans», «Genève» and «Lugano» start with their
      station, «Sustenpass» and «Passo del San Gottardo» with the pass,
      «Pizol» has the summit third; «Bahnhofstrasse 1 Zürich» starts with
      the addresses; «Cabane de Moiry», «Capanna Cristallina» found. Before,
      swisstopo's «Genève\n» label broke and the pass was dropped as a
      repeat of the inn by it (`search_test.go`).
- [ ] **Dragging the line** onto a nearby path: GraphHopper snaps the new point
      to the nearest foot path, which may be a road next to the trail.
- [ ] **Dragging onto another path** («Anderer Weg») on real trails: the
      ways that show while dragging are the ones hikers take (valley or
      ridge, left or right of a lake), and one is missing nowhere it should
      be; where there is none, the message says so. Alt (⌥) on Windows and
      Linux, where the window manager may take Alt-drag.
      2026-10-02, local: Mels → Wangs and Sarnen → Engelberg offer 5 ways,
      Grindelwald → Kleine Scheidegg 3, First → Bachalpsee and
      Lauterbrunnen → Wengen none.
- [ ] **Dragging the line on a touch screen** (iPhone Safari, an Android
      tablet): holding the line for 0.4 s takes it, a quick swipe still pans
      the map, two fingers still zoom.
- [ ] **Drop-downs with the keyboard** on Windows (Chrome, Edge, Firefox):
      arrowing through «Aus meinen Routen übernehmen», «Zu Sammlung
      hinzufügen», visibility and language acts only on Enter or when
      leaving the field.
- [ ] **Etappentour planen** over two weeks and more (e.g. the Via Alpina):
      how long the proposal takes, whether the nights are where one would
      stay, and the alternatives earlier and later; hut websites after
      `make places-import`.
      2026-10-01, local: Vaduz → Montreux through the Via Alpina's passes at
      6.5 h a day: 19 days in 7.6 s. The nights to judge.
- [ ] **Mehrere Wege vorschlagen** for journeys one knows (Thun → Zermatt,
      Engelberg → Meiringen, the Via Alpina in parts): are the ways ones
      hikers take, is one missing that should be there, and do the nights
      where one can change ways make sense?
      2026-10-01: Thun → Zermatt in 5 days, «Way 4: via Steinhaus» starts
      with a day of 36.4 km and 13 h 20 min.
- [x] **Dark mode** in Safari, Chrome and Firefox (system setting): every page
      readable, including dialogs, drop-downs, the photo lightbox and the
      elevation profile.
      Playwright 2026-10-01 (Chromium, Firefox 155, WebKit 26.6): every page,
      the bug report dialog, the lightbox and the profile: text contrast at
      least 4.5 against its background except the faint «404» (as in light);
      drop-downs take the dark colour scheme.
- [x] **The website on a phone** (iPhone Safari, an Android phone): the menu
      opens and closes, nothing scrolls sideways; on the map pages the map
      stays half the screen when the address bar hides and shows, the panel
      scrolls below it, and «Speichern» stays at the panel's bottom edge in
      the planner; tapping the map adds points; the ↑ ↓ × are easy to hit.
      Playwright 2026-10-01 (WebKit as iPhone 15, Chromium as Pixel 7): all
      of it, the address bar as a viewport 80 px taller and back. The
      elevation profile 616 px wide for a moment while a route page loaded:
      fixed 2026-10-02 (`phone.e2e.ts`).
- [x] **Old address**: links to `odysgeh.tellbow.ch` (shared routes, live
      shares, e-mails sent before) end on the same page at
      `alvyo.tellbow.ch`. Passkeys made on the old address do not work on the
      new one: log in with the password and add a passkey again.
      2026-10-01: 308 to the same path and query at alvyo.tellbow.ch.

- [ ] **Screenshots of bug reports** (41) in Safari, Chrome and Firefox: the
      page with its map, in dark mode too; the issue on GitHub links to the
      screenshot, which opens for moderators only.
      Playwright 2026-10-01: Chromium and Firefox show the map, light and
      dark; WebKit (Safari) left it empty, fixed 2026-10-02 (a first
      rendering thrown away; `bugs.e2e.ts` in WebKit). The link for
      moderators only is tested with a fake GitHub (`bugapi_test.go`); the
      real GitHub not tried.
- [x] **New kinds along the way** (48), after `places-import` has run with
      the new script in production: fire places, picnic spots, restaurants,
      toilets and cable car stations on the map and in a route's list; in a
      town, whether restaurants crowd the list.
      2026-10-01: in production, around Bern 50 fire places, 157 picnic spots,
      536 restaurants and 128 toilets, cable car stations at Grindelwald.
      They crowded the list (25 entries in Sargans' first 2.5 km); since
      2026-10-02 a town's fountains, restaurants, toilets … of a kind within
      1 km are one line («0–0.9 km · Restaurant, Café ×8»), on the website
      and in the app.

## Server

- [x] **Reminder e-mails** (54): for a journey starting in three weeks with
      nights not booked, «Übernachtungen buchen» arrives after 8:00 to the
      owner and those along; two days and one day before the others.
      2026-09-29, local with Mailpit: journeys starting in 21, 2 and 1 days;
      at 16:38 all three e-mails reached the owner and the one along.

- [ ] **Turns for imported Komoot tours**: planned ones get turns, recorded ones
      (GPS tracks) none or few; nothing announced along a straight leg.
- [x] **Long Watch hikes** (8 h, a position every second) upload within the
      50,000-point limit; the app sends points 5 m apart.
      2026-09-29, local: 8 h at 1 Hz along Gaflei – Sargans: 15,002 points
      after the app's 5 m rule (1.2 MB) and all 28,800 (2.4 MB) are taken in
      under 2 s as hikes of 8 h.
