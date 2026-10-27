---
name: release
description: Releases Alvyo to production - tags vX.Y.Z on main, waits for the image build, lets Flux deploy it and checks it. Only when the user asks for a release.
disable-model-invocation: true
---

# Release

A release deploys to production (https://alvyo.tellbow.ch). Confirm the
version with the user before tagging: fixes raise the patch number, new
features the minor one.

1. **Ready?** `main` is pushed and CI passed for its last commit:
   `gh run list -L 1 --branch main`. The end-to-end tests passed locally
   on that commit (`.claude/rules/e2e.md`). `docs/plan.md` describes what is in it
   (the «next» row of the release table).
2. **Record first:** in `docs/plan.md`, the «next» row becomes the X.Y.Z
   row with today's date, and «Was ist neu» gets a line for the people
   using Alvyo: `web/src/lib/news/releases.ts` and `news_X_Y_Z` in all four
   `web/messages/*.json` (what changed for them, in their words; skip
   releases with nothing they notice). Commit and push, and tag that
   commit. The `release` workflow takes the row as the GitHub Release's
   notes.
3. **Tag:**
   `git tag -s vX.Y.Z -m "Alvyo X.Y.Z: <what, in a few words>" <sha> && git push origin vX.Y.Z`
   (signed with the GPG key that signs the commits; the `release` workflow
   refuses a tag it cannot verify against `.github/release-signers.asc`)
4. **Images:** the `release` workflow builds `ghcr.io/tellbow/alvyo-{api,web,data-import,postgis,graphhopper}`.
   `gh run list -L 2` for its id, then `gh run watch <id> --exit-status`;
   its last job creates the GitHub Release (`gh release view vX.Y.Z`).
5. **Deploy:** Flux image automation sets the api, web and data-import tags
   in the deployment repository. Never edit them by hand: a manual
   bump was once reverted by the automation. With the kubeconfig and
   context from `CLAUDE.local.md`:
   - `flux reconcile image repository alvyo-api` (and `alvyo-web`, `alvyo-data-import`)
   - `flux reconcile image update flux-system`
   - `flux reconcile kustomization flux-system --with-source`

   postgis and graphhopper are pinned by hand in the deployment repository; change them
   only when their images changed (`infra/postgis`, `infra/graphhopper`).
6. **Check** (same kubeconfig and context):
   - `kubectl --context <context> -n alvyo rollout status deploy/api` and `deploy/web`
     (migrations run in the api's init container)
   - `curl -s https://alvyo.tellbow.ch/api/v1/openapi.json | jq -r .info.version` shows X.Y.Z
   - the logs have no errors: `kubectl --context <context> -n alvyo logs deploy/api --since=10m`
   - if an import script changed since the last release
     (`git diff vPREVIOUS -- infra/data-import`): the `places-import` and
     `tlm-import` cron jobs are suspended, so run the changed one by hand,
     e.g. `kubectl --context <context> -n alvyo create job --from=cronjob/places-import places-import-X-Y-Z`
7. **Afterwards:** if the app changed, offer the `iphone-install` and
   `android-install` skills, the `testflight` skill for TestFlight and
   then the `app-store` skill for the App Store.
