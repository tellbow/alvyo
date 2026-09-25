# Manual tests

What automated tests and the simulator cannot show. Tick off with the date and
the device; note anything odd.

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
- [ ] **Loops**: starting at the trailhead says nothing about arriving; the
      progress keeps going forward, «Ziel erreicht» at the end.
- [ ] **Location switched off mid-hike** (Control Centre or Settings): the
      banner says «Warte auf GPS …» until positions come again.
- [ ] **Logged out elsewhere** (or the session expired): opening the app shows
      the login, not «Server nicht erreichbar».
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
- [ ] **Out-and-back route** (to a summit and back the same way): the turns on
      the way back are announced, the progress keeps growing. The U-turn
      itself may not be announced.
- [ ] **Voice button**: off stops the prompts for this hike (it is on again
      at the next start).
- [ ] **Following on the map** at walking speed: the map glides to the position
      at zoom 15; panning stops following, the button brings it back.
- [ ] **Offline map without reception** (airplane mode): the saved route and its
      map open, the position shows on it, the turns are announced (saved with
      the map; a map saved before this version has none offline).
- [ ] **Saving an offline map** goes on after leaving the route screen, and a
      download broken off (reception lost, app in the background for long)
      continues where it stopped when saving again.
- [ ] **Saving an offline map in a hut's or station's Wi-Fi** that first shows
      a login page: the save fails and works once logged in to the Wi-Fi,
      without a broken map.
- [ ] **iCloud backup**: offline maps are not in it (Settings → your name →
      iCloud → Manage storage → Backups: Alvyo stays small).
- [ ] **App stopped mid-hike** (swipe it away, open it again): the route offers
      «Wanderung fortsetzen» and the hike goes on.
- [ ] **Upload later**: finish a hike without reception; once online, it goes up
      when the route list loads and shows in «Meine Routen».
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

- [ ] **Two accounts on one phone**: record a hike offline, log out, log in
      as someone else: the hike is not uploaded to them, nor resumed; back
      in the first account it uploads.
- [ ] **Starting a hike on another route** while one is recorded asks
      first; «Abbrechen» leaves the running hike as it was.
- [ ] **A stage ticked off**: after hiking a stage's route, «Etappe als
      gewandert markieren» in the message marks it (online); in the journey
      the check next to a stage does the same and back.

- [ ] **A shared hike on a real hike** (production, real e-mail): the contact
      gets the link, follows the position (with dead spots in a valley),
      «Später» works; ended without a connection, the end reaches the server
      once back online and nobody is alerted. An overdue alert (set the end
      a few minutes ahead) reaches contact and hiker, and the all-clear
      after «Später».
- [ ] **Alvyo look in light and dark** (Settings → Display, and «Automatic» at
      dusk): the bar at the bottom, the record button (opens the hike in
      progress, else the hint), cards, fonts and the map screens readable in
      both; the new icon on the home screen.

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
- [ ] **Dark mode** in Safari, Chrome and Firefox (system setting): every page
      readable, including dialogs, drop-downs, the photo lightbox and the
      elevation profile.
- [ ] **Old address**: links to `odysgeh.tellbow.ch` (shared routes, live
      shares, e-mails sent before) end on the same page at
      `alvyo.tellbow.ch`. Passkeys made on the old address do not work on the
      new one: log in with the password and add a passkey again.

## Server

- [ ] **Turns for imported Komoot tours**: planned ones get turns, recorded ones
      (GPS tracks) none or few; nothing announced along a straight leg.
- [ ] **Long Watch hikes** (8 h, a position every second) upload within the
      50,000-point limit; the app sends points 5 m apart.
