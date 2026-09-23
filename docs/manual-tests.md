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
- [ ] **Out-and-back routes and loops**: the progress keeps going forward on the
      way back.
- [ ] **Remaining time** compared with the time actually needed, at the pace set
      in the account.
- [ ] **Following on the map** at walking speed: the map glides to the position
      at zoom 15; panning stops following, the button brings it back.
- [ ] **Offline map without reception** (airplane mode): the saved route and its
      map open, the position shows on it.
- [ ] **App stopped mid-hike** (swipe it away, open it again): the route offers
      «Wanderung fortsetzen» and the hike goes on.
- [ ] **Upload later**: finish a hike without reception; once online, it goes up
      when the route list loads and shows in «Meine Routen».
- [ ] **Apple Watch import** of real «Wandern» and «Gehen (im Freien)» workouts:
      the track and time are right; a paused workout (several route parts)
      comes out as one hike; a workout without GPS says so.
- [ ] **Health access refused**: the watch screen explains where to allow it.
- [ ] **Free Apple ID expiry**: after 7 days the app no longer starts;
      `flutter run --release` renews it.

## Web

- [ ] **Place search** with more names: villages, peaks, passes, huts, stops and
      addresses, also French and Italian names.
- [ ] **Dragging the line** onto a nearby path: GraphHopper snaps the new point
      to the nearest foot path, which may be a road next to the trail.
- [ ] Dragging the line on a **touch screen** is not built yet (mouse only).

## Server

- [ ] **Long Watch hikes** (8 h, a position every second) upload within the
      50,000-point limit; the app sends points 5 m apart.
