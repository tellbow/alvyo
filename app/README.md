# Alvyo app

Flutter app for iOS and Android: log in, list your routes, show a route on
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

The Apple Watch app (`ios/AlvyoWatch`, SwiftUI, watchOS 10, inside the iOS
app) shows the hike the phone navigates or records: the next turn, the
route line (or the track) with one's position, what is still to go, the
time underway; it pauses and stops the hike, starts one (on a tour, or
without), and taps the wrist when one leaves the route while it is on
screen. The phone does the GPS, recording and upload; the two talk over
WatchConnectivity (`ios/Runner/WatchBridge.swift`, channel `alvyo/watch`,
`lib/navigation/watch.dart`). iOS starts the GPS only while the app is open,
so a start asked for on the watch while the phone is locked waits until
Alvyo is opened (up to 10 minutes). The watch's texts are in its own
`Localizable.strings` (German keys); building it needs the watchOS platform
in Xcode (Settings → Components).

Android (issue 8) has all of this except «Berge erkennen» (no camera view
yet) and the watch import (Health Connect to come); both are hidden there.
Recording goes on with the screen locked through a foreground service with
a notification, started while the app is open, so the app needs no
background location. The native pieces are in `MainActivity.kt` (spoken
turns with Android's text-to-speech); offline maps and the login stay out of
backups by `res/xml/*_rules.xml`. Links to alvyo.tellbow.ch's routes,
journeys, collections and invites open the app (app links: the release
key's fingerprint is in `web/static/.well-known/assetlinks.json`; a new key
needs it changed there). The APK of each release is on GitHub; the
Play Store is to come.

## Run

```sh
flutter run -d <simulator or phone>   # server: https://alvyo.tellbow.ch or http://localhost:5173
```

The login asks for the server only in debug builds (`flutter run`, the
tests); release builds (App Store, Play Store, the APKs, `flutter run
--release`) always use https://alvyo.tellbow.ch.

On an iPhone (by cable, Developer Mode on) with a free Apple ID: add the
Apple ID in Xcode → Settings → Accounts and create an «Apple Development»
certificate there (Manage Certificates). Flutter then picks the team from the
certificate and registers the phone:

```sh
flutter run --release -d <phone>   # a release build also starts without the Mac
```

A free Apple ID cannot sign Sign in with Apple and universal links
(Associated Domains): remove both from `ios/Runner/Runner.entitlements` for
such a build, without committing it.

If `security find-identity -v -p codesigning` finds no valid identity, the
keychain lacks Apple's intermediate certificate: install
<https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer>. The first start
needs the developer to be trusted on the phone (Settings → General → VPN &
Device Management), and a free Apple ID's apps stop after 7 days: run the
command again.

For TestFlight or the App Store (needs a paid Apple developer account), the
version comes from the last release tag and the build number grows with
every commit (`pubspec.yaml`'s `0.1.0+1` is only the fallback; `flutter
run` cannot set them):

```sh
FIREBASE_ANALYTICS_WITHOUT_ADID=true \
flutter build ipa --build-name=$(git describe --tags --abbrev=0 | sed 's/^v//') \
  --build-number=$(git rev-list --count HEAD) \
  --dart-define=ALVYO_VERSION=$(git describe --tags --always)
```

Uploading that build: `xcodebuild -exportArchive` with
`ios/ExportOptions-upload.plist` signs it with an «Apple Distribution»
certificate in the Mac's keychain and the App Store profiles «Alvyo App
Store» and «Alvyo Watch App Store» (the watch app, App ID
`ch.tellbow.alvyo.watchkitapp`), and sends it to App Store Connect with an App Store Connect API key
(the `testflight` skill has the steps). Another Mac needs its own
distribution certificate, a profile with it and a key.

The App Store's screenshots, header and search result picture, and the
scripts that make them: [store/README.md](store/README.md).

### Android

The emulator (once: `brew install openjdk@17` and `brew install --cask
android-commandlinetools`, then with `sdkmanager` the platform, build tools,
emulator and a system image, and `flutter config --android-sdk
/opt/homebrew/share/android-commandlinetools`):

```sh
emulator -avd alvyo -gpu host &               # an AVD made with avdmanager
adb reverse tcp:5173 tcp:5173                 # localhost:5173 on the emulator is the Mac's
flutter run -d emulator-5554
```

`adb reverse` is lost when the emulator restarts or adb loses it. The web
dev server listens on 127.0.0.1 for it (`web/vite.config.ts`). Debug builds
may use plain HTTP (`src/debug/AndroidManifest.xml`); release builds only
HTTPS.

**Release key.** A release APK is signed with the key in
`android/key.properties`, else with the debug key (`flutter run --release`
works without it). Phones install a later APK over an earlier one only if
both have the same key, so it is made once and kept (in the password
manager as well):

```sh
keytool -genkeypair -keystore alvyo-release.jks -storetype PKCS12 -alias alvyo \
  -keyalg RSA -keysize 4096 -validity 10000 -dname "CN=Alvyo"
gh secret set ANDROID_KEYSTORE < <(base64 -i alvyo-release.jks)
gh secret set ANDROID_KEYSTORE_PASSWORD             # the password given to keytool
keytool -list -keystore alvyo-release.jks -alias alvyo | grep SHA-256   # into assetlinks.json
```

The release workflow writes `key.properties` from these secrets and adds
`alvyo-<version>.apk` to the GitHub Release; CI builds the APK with the
debug key. Locally, with the version as for the App Store:

```sh
flutter build apk --release --build-name=$(git describe --tags --abbrev=0 | sed 's/^v//') \
  --build-number=$(git rev-list --count HEAD) \
  --dart-define=ALVYO_VERSION=$(git describe --tags --always)
```

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
  and back, arrival, recording; the spoken turns (a fake voice) and the
  native voice channel (iOS and Android);
- `journey_test.dart` opens the journey, saves all stages offline and opens it
  and a stage with an unreachable server;
- `community_test.dart` switches the look and the language in the profile,
  changes the route's description, likes and comments on it, adds it to a
  new collection, changes a stage's accommodation and opens the feed and
  the map of one's tours, putting everything back;
- `watch_test.dart` sends the tours and a hike through the native watch
  bridge and pauses it on the phone; with a watch simulator paired
  (`xcrun simctl pair <watch> <phone>`) and
  `build/ios/Debug-watchsimulator/AlvyoWatch.app` installed on it while the
  test runs (`--dart-define=WATCH_HOLD=30` holds each state), the watch
  shows them;
- `gps_test.dart` uses the real GPS path and needs the simulator to grant the
  location and move along the route, started once the test app is installed:

  ```sh
  xcrun simctl privacy <simulator> grant location ch.tellbow.alvyo
  xcrun simctl location <simulator> start --speed=30 <lat,lon> <lat,lon> …
  ```

The watch app's buttons are tapped by its UI test (`ios/AlvyoWatchUITests`,
scheme `AlvyoWatch`, in German). `testButtons` runs on its own against a
made-up phone:

```sh
cd ios && xcodebuild test -project Runner.xcodeproj -scheme AlvyoWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 12 (46mm)' \
  -only-testing:AlvyoWatchUITests/AlvyoWatchUITests/testButtons
```

`testWithPhone` pauses, carries on and finishes a hike on the paired iPhone
simulator over WatchConnectivity: start `flutter test
integration_test/watch_test.dart -d <phone> --dart-define=WATCH_FROM_WATCH=true`,
and once it prints «waiting for the watch», the same `xcodebuild test` with
`TEST_RUNNER_ALVYO_PHONE=1` and `-only-testing:…/testWithPhone` (build it
first with `build-for-testing`, then `test-without-building`, so the phone
does not wait for the build).

On the Android emulator the same tests run with `-d emulator-5554` after
`adb reverse tcp:5173 tcp:5173` (offline, navigate and journey checked
2026-10-12); `flutter test` installs the app afresh for each file, so it
logs in each time. If a run hangs on the splash screen, an earlier run was
cut off: `adb shell am force-stop ch.tellbow.alvyo` and run again.

What only a real phone and a real hike can show is listed in
`docs/manual-tests.md`.
