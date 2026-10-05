---
name: screenshot
description: Take a screenshot of a new feature or a fixed bug on the website (Playwright against the local dev server) or in the app (iOS simulator), check it, and show it to the user in their terminal (Ghostty, Kitty graphics protocol). Use after finishing user-visible work, as the screenshots rule says.
---

# Screenshot a feature and show it

Screenshots go to the scratchpad directory, never into the repository.

## 1. Local stack with the demo account

`make infra-up`; the API (`go run ./api/cmd/alvyo serve` with
`ALVYO_DATABASE_URL`) and `cd web && bun run dev`. Use port 5173: the API
checks the Origin against `ALVYO_PUBLIC_URL`, so logins from other ports
fail. The demo account `appdemo` / `sehr-geheim-123` has the route
«Sargans–Weisstannen» (48 points along the way) and the journey «Via Alpina».

## 2a. Website: Playwright

A small script with the web app's Playwright (not `bunx playwright test`):

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

Run it with `cd web && bun script.mjs /scratchpad/shot.png`. The page
is in German, so find things by German labels or test ids. Take light and
dark when colours changed, and 390 px wide when the phone layout is
affected.

## 2b. App: iOS simulator

Boot a simulator (`xcrun simctl list devices booted`). If a notification
permission dialog from an earlier run is in the way, reboot it. Put the app
in the state with a throwaway integration test that navigates there, then
prints `READY` and pumps for a few seconds. Start the test in the
background, wait for `READY` in its output, then run
`xcrun simctl io <id> screenshot /scratchpad/shot.png`. Delete the
throwaway test afterwards. The simulator runs in English.

## 3. Check, then show

Look at the image yourself first (Read), and fix what is wrong before
showing it. Then show it to the user:

```sh
python3 .claude/skills/screenshot/show.py /scratchpad/shot.png [/scratchpad/dark.png] [--cols 100]
```

This writes the image to the terminal Claude Code runs in (the user's
choice, though Claude Code's prompts may be drawn over or under it; at most
100 columns, fitted to the terminal's height). `--window` opens a new
Ghostty window instead. Show it right before the final reply, not before a
question to the user, and say in the reply what each image shows. Stop
the API and the dev server afterwards if you started them.
