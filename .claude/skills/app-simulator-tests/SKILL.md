---
name: app-simulator-tests
description: Run the odysgeh app's integration tests on the iOS simulator against the local dev stack (dev containers, API, web dev server, demo account). Use after changing app screens, navigation, recording, offline maps or the native Swift code.
---

# App integration tests on the simulator

The tests in `app/integration_test/` log in to the local server at
http://localhost:5173 as the demo account `appdemo` / `sehr-geheim-123`,
which has the route «Sargans–Weisstannen» and the journey «Via Alpina»
(`app/README.md` says how they were made).

1. **Dev stack:** `make infra-up`, then wait until GraphHopper answers:
   `until curl -sf localhost:8989/health; do sleep 3; done`.
2. **API and web** (in the background, as in daily work):
   `ODYSGEH_DATABASE_URL=… go run ./api/cmd/odysgeh migrate`, then `… serve`,
   and `cd web && bun run dev`. Ready when
   `curl -sf localhost:5173/api/v1/auth/providers` answers.
3. **Simulator:** `xcrun simctl list devices booted`; if none is booted,
   `xcrun simctl boot <id>` and `xcrun simctl bootstatus <id> -b`.
4. **Run:**
   `cd app && flutter test integration_test/offline_test.dart integration_test/navigate_test.dart integration_test/journey_test.dart -d <simulator id>`.
   `gps_test.dart` needs a simulated location route set up by hand
   (`app/README.md`).
5. **Afterwards:** stop the API and the web dev server.

Pitfalls:
- A notification permission dialog left from an earlier run blocks the app:
  reboot the simulator (`xcrun simctl shutdown <id> && xcrun simctl boot <id>`).
- The simulator runs in English: find widgets by key, not by German text.
- Wait for tab changes and page transitions before tapping (pump a second).
- To see what the app shows: `xcrun simctl io <id> screenshot /path/to/shot.png`.
