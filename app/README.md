# Alvyo app

Flutter app for iOS (Android later): log in, list your routes, show a route on
the swisstopo national map and save it offline, and hike it: your position on
the map, how far and how long it is still, the next turn, also spoken (about
100 m before and at the junction, with the screen locked too), a warning (also
as a notification) when you leave the route, and a recording of the hike. The
turns come from the API (`GET /routes/{id}/turns`: the line matched onto the
path network with GraphHopper; recorded GPS tracks get none) and are saved
with the offline map. Offline maps are
PMTiles packs built by the API (`docs/adr/0004-offline-maps.md`); saved routes
open without a connection. Finished hikes are uploaded as routes (`POST
/hikes`), right away or once online, and show in «Meine Routen» with the date.
Journeys are in their own tab: their stages with date, numbers, stops, gaps
and accommodation; each stage opens as a route, and «Save all stages offline»
saves every stage's map and keeps the journey for opening it offline.
Hikes recorded with the Apple Watch's Workout app («Hiking» or «Outdoor Walk»)
are imported from Apple Health the same way (the watch button in the list;
HealthKit works with a free Apple ID).

## Run

```sh
flutter run -d <simulator or phone>   # server: https://alvyo.tellbow.ch or http://localhost:5173
```

On an iPhone (by cable, Developer Mode on) with a free Apple ID: add the
Apple ID in Xcode → Settings → Accounts and create an «Apple Development»
certificate there (Manage Certificates). Flutter then picks the team from the
certificate and registers the phone:

```sh
flutter run --release -d <phone>   # a release build also starts without the Mac
```

If `security find-identity -v -p codesigning` finds no valid identity, the
keychain lacks Apple's intermediate certificate: install
<https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer>. The first start
needs the developer to be trusted on the phone (Settings → General → VPN &
Device Management), and a free Apple ID's apps stop after 7 days: run the
command again.

## Tests

```sh
flutter analyze
flutter test                                    # unit tests
flutter test integration_test -d <simulator>    # against the local dev stack
```

The integration tests expect the API and the web dev server (:5173) from
`docs/development.md`, an account `appdemo` / `sehr-geheim-123`, its route
«Sargans–Weisstannen» and its journey «Via Alpina» (a GPX with the tracks
«Gaflei – Sargans» and «Sargans – Weisstannen», imported as a journey):

- `offline_test.dart` saves the route offline and opens it with an
  unreachable server;
- `navigate_test.dart` hikes it with made-up positions: progress, off the route
  and back, arrival, recording; the spoken turns (a fake voice) and the iOS
  voice channel;
- `journey_test.dart` opens the journey, saves all stages offline and opens it
  and a stage with an unreachable server;
- `gps_test.dart` uses the real GPS path and needs the simulator to grant the
  location and move along the route, started once the test app is installed:

  ```sh
  xcrun simctl privacy <simulator> grant location ch.tellbow.alvyo
  xcrun simctl location <simulator> start --speed=30 <lat,lon> <lat,lon> …
  ```

What only a real iPhone and a real hike can show is listed in
`docs/manual-tests.md`.
