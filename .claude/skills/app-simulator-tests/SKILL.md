---
name: app-simulator-tests
description: Runs the Alvyo app's integration tests on the iOS simulator or the Android emulator against the local dev stack (dev containers, API, web dev server, demo account). Use after changing app screens, navigation, recording, offline maps or the native Swift or Kotlin code.
---

# App integration tests on the simulator

The tests in `app/integration_test/` log in to the local server at
http://localhost:5173 as the demo account `appdemo` / `sehr-geheim-123`,
which has the route «Sargans–Weisstannen» and the journey «Via Alpina»
(`app/README.md` says how they were made).

1. **Dev stack:** `make infra-up`, then wait until GraphHopper answers:
   `until curl -sf localhost:8989/health; do sleep 3; done`.
2. **API and web** (in the background, as in daily work):
   `ALVYO_DATABASE_URL=… go run ./api/cmd/alvyo migrate`, then `… serve`,
   and `cd web && bun run dev`. Ready when
   `curl -sf localhost:5173/api/v1/auth/providers` answers.
3. **Simulator:** `xcrun simctl list devices booted`; if none is booted,
   `xcrun simctl boot <id>` and `xcrun simctl bootstatus <id> -b`.
4. **Run:**
   `cd app && flutter test integration_test/offline_test.dart integration_test/navigate_test.dart integration_test/journey_test.dart -d <simulator id>`.
   `gps_test.dart` needs a simulated location route set up by hand
   (`app/README.md`).
5. **Afterwards:** stop the API and the web dev server.

On the **Android emulator** (`app/README.md`, «Android»; AVD `alvyo`):
boot it with `emulator -avd alvyo -gpu host` (the SDK is in
`/opt/homebrew/share/android-commandlinetools`, JDK 17 from
`/opt/homebrew/opt/openjdk@17`), wait for
`adb shell getprop sys.boot_completed` to say 1, then
`adb reverse tcp:5173 tcp:5173` and run step 4 with `-d emulator-5554`,
one file per `flutter test` (set the reverse again before each).

Pitfalls:
- Android: «Connection refused» means `adb reverse` is gone (the emulator
  restarted or adb lost it), or the web dev server listens on ::1 only
  (`web/vite.config.ts` sets 127.0.0.1). A run that hangs on the splash
  screen follows a run that was cut off: `adb shell am force-stop
  ch.tellbow.alvyo`. Without `-gpu host` the emulator drops adb under load.
- Android: `flutter test` uninstalls the app after each file, so every file
  logs in again and permissions are asked again.
- To see what the emulator shows: `adb exec-out screencap -p > shot.png`.
- A notification permission dialog left from an earlier run blocks the app:
  reboot the simulator (`xcrun simctl shutdown <id> && xcrun simctl boot <id>`).
- The simulator runs in English: find widgets by key, not by German text.
- Wait for tab changes and page transitions before tapping (pump a second).
- To see what the app shows: `xcrun simctl io <id> screenshot /path/to/shot.png`.
