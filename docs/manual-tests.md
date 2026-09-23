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
- [ ] **Loops**: the progress keeps going forward past the start.
- [ ] **Remaining time** compared with the time actually needed, at the pace set
      in the account.
- [ ] **Spoken turns** on a planned route, phone in the pocket with the screen
      locked: «In 100 Metern links abbiegen» about 100 m before a junction and
      «Links abbiegen» about 20 m before it, then «Ziel erreicht». Heard over
      music (turned down meanwhile) and with the silent switch on; the voice
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
- [ ] **iCloud backup**: offline maps are not in it (Settings → your name →
      iCloud → Manage storage → Backups: odysgeh stays small).
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

## Web

- [ ] **Place search** with more names: villages, peaks, passes, huts, stops and
      addresses, also French and Italian names.
- [ ] **Dragging the line** onto a nearby path: GraphHopper snaps the new point
      to the nearest foot path, which may be a road next to the trail.
- [ ] Dragging the line on a **touch screen** is not built yet (mouse only).

## Server

- [ ] **Turns for imported Komoot tours**: planned ones get turns, recorded ones
      (GPS tracks) none or few; nothing announced along a straight leg.
- [ ] **Long Watch hikes** (8 h, a position every second) upload within the
      50,000-point limit; the app sends points 5 m apart.
