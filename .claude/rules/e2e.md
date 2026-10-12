# End-to-end tests before a release

The web end-to-end tests (`web/tests/e2e`) run only locally: GitHub
Actions' free minutes are too few for the graph build and the stack.

Before a release (a `v*` tag, the `release` skill), run them all and tag
only when they pass:

1. The dev stack is up: `make infra-up`, GraphHopper healthy
   (`curl -fs http://localhost:8989/health`).
2. `cd web && CI=1 bunx playwright test` (`CI=1`: builds the API and web
   fresh instead of reusing running servers, and one worker).
3. A failure stops the release: fix it, or tell the user and let them
   decide. Do not tag around it.
