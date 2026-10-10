---
paths:
  - "web/**"
---

# SvelteKit web app

- SvelteKit 3, Svelte 5 runes (`$state`, `$derived`, `$effect`, `$props`),
  TypeScript, Tailwind, MapLibre GL. Its options are in `vite.config.ts`;
  `src/lib` is imported as `#lib/…` with the file's extension (`.js` for
  `.ts`, `.svelte.js` for `.svelte.ts`).
- API calls through `api()` from `#lib/api/client.js` (openapi-fetch, typed from
  the generated `schema.d.ts`). A request that gets no answer comes back as a
  503 answer, so handling `data` and `error` covers offline too.
- Texts: `m.key()` from `#lib/paraglide/messages.js`; every key goes into all four
  `web/messages/*.json` (tab-indented).
- No `{@html}`; map markers are built with `textContent`.
- Unit tests: `*.spec.ts` next to the code (vitest).
- End-to-end tests: `tests/e2e/*.e2e.ts` with `./fixtures` (they fail on any
  console error; `goto` and `reload` wait until the page is hydrated, also in
  contexts from `browser.newContext()`). Sign up users with `signUp(page.request, { data })`
  (`./accounts`: signing up alone does not log in) and a unique name (time
  plus a random suffix: tests run in parallel). Before mouse gestures on the
  map, wait for its state (e.g. the canvas cursor turning to `pointer` over
  the line). E-mails come from Mailpit (`tests/e2e/mailpit.ts`);
  `/verify-email` names the account and confirms on `verify-confirm`, then
  shows `verify-status`.
- `bun run lint` (prettier with tabs, eslint) and `bun run check`.
