---
name: screenshot-capture
description: Takes screenshots of one state of the Alvyo website (Playwright against the local dev server) or app (iOS simulator) and returns the image paths. Called by the screenshot skill with what to capture; not for use on its own.
context: fork
model: haiku
background: false
user-invocable: false
argument-hint: <what to show, how to get there, web or app, variants, output directory>
---

# Capture screenshots

Take the screenshots described here and report back. You do not see the
conversation that asked for them: everything you get is this request.

$ARGUMENTS

Only capture. Do not change the repository's code to fix what you see,
and do not judge the design: the caller does that. The one file you may add
is a throwaway integration test for the app (2b), deleted afterwards.
Write the images to the output directory named above, never into the
repository.

## 1. Local stack with the demo account

Reuse what already runs; start only what is missing, and remember what you
started.

- Dev containers: `make infra-up`, then
  `until curl -sf localhost:8989/health; do sleep 3; done` (GraphHopper takes
  about 2 minutes after a fresh start).
- API, in the background:
  `export ALVYO_DATABASE_URL='postgres://alvyo:alvyo@localhost:5432/alvyo?sslmode=disable'`,
  `go run ./api/cmd/alvyo migrate`, then `go run ./api/cmd/alvyo serve`.
- Web, in the background: `cd web && bun run dev`. Ready when
  `curl -sf localhost:5173/api/v1/auth/providers` answers.

Use port 5173: the API checks the Origin against `ALVYO_PUBLIC_URL`, so
logins from other ports fail. The demo account `appdemo` /
`sehr-geheim-123` has the route «Sargans–Weisstannen» (48 points along the
way) and the journey «Via Alpina».

## 2a. Website: Playwright

If the request comes with a script, run it as it is. Otherwise write a
small one in the output directory, with the web app's Playwright (not
`bunx playwright test`):

```js
import { chromium } from '/Users/adrian/git/private/alvyo/web/node_modules/playwright/index.mjs';
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 1440, height: 900 }, locale: 'de-CH', colorScheme: 'light' });
await p.goto('http://localhost:5173/login');
await p.getByLabel(/Benutzername|E-Mail/).first().fill('appdemo');
await p.getByLabel('Passwort').fill('sehr-geheim-123');
await p.getByRole('button', { name: 'Anmelden' }).click();
await p.waitForURL((u) => !u.pathname.includes('login'));
// … go to the feature, put it in its state (hover, open, filled) …
await p.screenshot({ path: process.argv[2] }); // or { clip: {x, y, width, height} } for a detail
await b.close();
```

Run it with `cd web && bun <script> <outdir>/shot.png`. The page is in
German: find things by German labels or test ids. For dark mode set
`colorScheme: 'dark'`; for the phone layout a viewport 390 px wide.

## 2b. App: iOS simulator

1. `xcrun simctl list devices booted`; if none is booted,
   `xcrun simctl boot <id>` and `xcrun simctl bootstatus <id> -b`. If a
   notification permission dialog from an earlier run is in the way,
   reboot it (`xcrun simctl shutdown <id> && xcrun simctl boot <id>`).
2. Write a throwaway test `app/integration_test/screenshot_tmp_test.dart`
   that starts the app, logs in and navigates to the state, then prints
   `READY` and pumps for 20 seconds. Copy the login and the `waitFor`
   helper from `app/integration_test/offline_test.dart`. The simulator runs
   in English: find widgets by key, not by German text, and pump a second
   after each tab change or page transition.
3. Start it in the background:
   `cd app && flutter test integration_test/screenshot_tmp_test.dart -d <id>`.
   Wait for `READY` in its output, then
   `xcrun simctl io <id> screenshot <outdir>/app.png`.
4. Delete the throwaway test.

## 3. Check and report

Open each image (Read) only to see that it shows the requested state, not
the login page, an error, a spinner or a dialog in the way. If it does not,
try once more; then report what went wrong instead of guessing further.

Stop the API, the web dev server and the test you started; leave the dev
containers running.

Answer with one line per image: its absolute path and what it shows (page
or screen, state, light or dark, width). Then, if any, what could not be
captured and why (the error message, the last step that worked).
