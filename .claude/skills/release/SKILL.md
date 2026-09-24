---
name: release
description: Release odysgeh to production - tag vX.Y.Z on main, wait for the image build, let Flux deploy it and check it. Only when the user asks for a release.
disable-model-invocation: true
---

# Release

A release deploys to production (https://odysgeh.tellbow.ch). Confirm the
version with the user before tagging: fixes raise the patch number, new
features the minor one.

1. **Ready?** `main` is pushed and CI passed for its last commit:
   `gh run list -L 1 --branch main`. `docs/plan.md` describes what is in it
   (the «next» row of the release table).
2. **Tag:**
   `git tag -a vX.Y.Z -m "odysgeh X.Y.Z: <what, in a few words>" <sha> && git push origin vX.Y.Z`
3. **Images:** the `release` workflow builds `ghcr.io/tellbow/odysgeh-{api,web,data-import,postgis,graphhopper}`.
   `gh run list -L 2` for its id, then `gh run watch <id> --exit-status`.
4. **Deploy:** Flux image automation sets the api, web and data-import tags
   in the gitops repo (`cluster/odysgeh`). Never edit them by hand: a manual
   bump was once reverted by the automation. With
   `KUBECONFIG=~/.kube/k3s.yaml` and `--context rk1`:
   - `flux reconcile image repository odysgeh-api` (and `odysgeh-web`, `odysgeh-data-import`)
   - `flux reconcile image update flux-system`
   - `flux reconcile kustomization flux-system --with-source`

   postgis and graphhopper are pinned by hand in the gitops repo; change them
   only when their images changed (`infra/postgis`, `infra/graphhopper`).
5. **Check** (same `KUBECONFIG`):
   - `kubectl --context rk1 -n odysgeh rollout status deploy/api` and `deploy/web`
     (migrations run in the api's init container)
   - `curl -s https://odysgeh.tellbow.ch/api/v1/openapi.json | jq -r .info.version` shows X.Y.Z
   - the logs have no errors: `kubectl --context rk1 -n odysgeh logs deploy/api --since=10m`
6. **Record:** in `docs/plan.md`, the «next» row becomes the X.Y.Z row with
   today's date; commit and push. If the app changed, offer the
   `iphone-install` skill.
