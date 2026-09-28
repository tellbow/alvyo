# Manual tests

What automated tests cannot show. Tick off with the date and the device; note
anything odd. What the simulator could show was checked there with scripted
runs against the dev stack (the notes); the rest needs a phone or a hike.

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
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): panning cannot be
      scripted in the simulator (the map is a native view).
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
- [ ] **App stopped mid-hike** (swipe it away, open it again): the route offers
      «Wanderung fortsetzen» and the hike goes on.
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): with the files a stopped
      app leaves: the route offers «Wanderung fortsetzen»; swiping the app
      away itself only on a phone.
- [x] **Upload later**: finish a hike without reception; once online, it goes up
      when the route list loads and shows in «Meine Routen».
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): hike finished with the
      server unreachable; once online the route list uploaded it and shows it.
- [ ] **Apple Watch import** of real «Wandern» and «Gehen (im Freien)» workouts:
      the track and time are right; a paused workout (several route parts)
      comes out as one hike; a workout without GPS says so.
- [ ] **Health access refused**: the watch screen explains where to allow it.
- [ ] **Journeys** with more stages (a real multi-week one): «Save all stages
      offline» with a mobile connection, leaving the screen meanwhile; the
      journey and every stage open in airplane mode. Only tried with two
      stages on the local server.
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
- [ ] **A stage ticked off**: after hiking a stage's route, «Etappe als
      gewandert markieren» in the message marks it (online); in the journey
      the check next to a stage does the same and back.

- [ ] **A shared hike on a real hike** (production, real e-mail): the contact
      gets the link, follows the position (with dead spots in a valley),
      «Später» works; ended without a connection, the end reaches the server
      once back online and nobody is alerted. An overdue alert (set the end
      a few minutes ahead) reaches contact and hiker, and the all-clear
      after «Später».
- [ ] **A shared hike with reception that stalls** (a weak signal, not none):
      positions go out again once it is back, and «Beenden» returns within
      about 10 s.
- [x] **Alvyo look in light and dark** (Settings → Display, and «Automatic» at
      dusk): the bar at the bottom, the record button (opens the hike in
      progress, else the hint), cards, fonts and the map screens readable in
      both; the new icon on the home screen.
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): screenshots of the
      lists, a route with photos and comments, a journey, a stage, the feed
      and the profile, in light and dark (switched in the profile).
- [ ] **Huts on the map**: the layer button on the route, navigation and
      planning maps switches «Hütten» and «Hotels und Campingplätze», the
      choice holds on the next screen and after a restart; a tap on a dot
      opens its sheet, not the thing under it; offline nothing breaks.
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): the choice holds after a
      restart; tapping a dot only on a phone (taps on the map cannot be
      scripted).
- [ ] **Route planen** on the phone: tapping the map adds a point, a hut's
      «Als Routenpunkt hinzufügen» too; the line and the dots follow as
      legs arrive; the sheet drags well over the map and the search results
      stay above the keyboard; the saved route opens, saves offline and
      navigates; the time at one's pace matches the website.
- [ ] **Etappentour planen** on the phone: the map at 40 % with the panel
      usable while typing (a decimal comma on the Swiss keyboard); the days
      in their colours, the other ways grey and a tap on one chooses it;
      «Ab hier weiter auf Weg N»; the created journey opens.
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
- [ ] **Entdecken**: starts at one's position when location is already
      allowed and never asks for it; lines in colour, redrawn after moving
      the map or a filter; the offline message in airplane mode; another
      account's public route saves offline, is hiked and the hike uploads.
      Simulator 2026-09-28 (iPhone 17 Pro, iOS 26.5): the offline message
      shows; the rest on a phone.

- [ ] **Photos from the phone**: «Foto aufnehmen» asks for the camera once
      and adds the photo; several from the library go up one after the
      other (HEIC too); photos taken along the route show on the website's
      map. The large view swipes, zooms and deletes.
- [ ] **Sharing from the phone**: «Link senden …» opens the share sheet
      (Messages, WhatsApp, Mail) with the link, which opens the route or
      journey; «GPX teilen …» saves to Files and imports into another app
      (a journey as a ZIP of its stages).
- [ ] **Public transport on a stage**: the SBB links open the SBB app or
      sbb.ch with the stops and the day; «Verbindungen von hier zum Start»
      asks for the location only if not yet decided, finds the nearest stop
      and shows connections with platforms and delays.
- [ ] **Language and look chosen in the profile**: the whole app changes at
      once and keeps it after a restart; «Automatisch» follows the iPhone
      again (also its dark mode at dusk); e-mails come in the chosen
      language.
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

## Web

- [ ] **Place search** with more names: villages, peaks, passes, huts, stops and
      addresses, also French and Italian names.
- [ ] **Dragging the line** onto a nearby path: GraphHopper snaps the new point
      to the nearest foot path, which may be a road next to the trail.
- [ ] **Dragging onto another path** («Anderer Weg») on real trails: the
      alternative GraphHopper offers is the path meant (valley or ridge, left
      or right of a lake); where none is, the leg through the release point
      does not double back. Alt (⌥) on Windows and Linux, where the window
      manager may take Alt-drag.
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
- [ ] **Mehrere Wege vorschlagen** for journeys one knows (Thun → Zermatt,
      Engelberg → Meiringen, the Via Alpina in parts): are the ways ones
      hikers take, is one missing that should be there, and do the nights
      where one can change ways make sense?
- [ ] **Dark mode** in Safari, Chrome and Firefox (system setting): every page
      readable, including dialogs, drop-downs, the photo lightbox and the
      elevation profile.
- [ ] **The website on a phone** (iPhone Safari, an Android phone): the menu
      opens and closes, nothing scrolls sideways; on the map pages the map
      stays half the screen when the address bar hides and shows, the panel
      scrolls below it, and «Speichern» stays at the panel's bottom edge in
      the planner; tapping the map adds points; the ↑ ↓ × are easy to hit.
- [ ] **Old address**: links to `odysgeh.tellbow.ch` (shared routes, live
      shares, e-mails sent before) end on the same page at
      `alvyo.tellbow.ch`. Passkeys made on the old address do not work on the
      new one: log in with the password and add a passkey again.

## Server

- [ ] **Turns for imported Komoot tours**: planned ones get turns, recorded ones
      (GPS tracks) none or few; nothing announced along a straight leg.
- [ ] **Long Watch hikes** (8 h, a position every second) upload within the
      50,000-point limit; the app sends points 5 m apart.
