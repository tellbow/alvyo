---
name: app-store
description: Publishes a release of the Alvyo iOS app on the App Store through the App Store Connect API - the App Store version, «Neuerungen» in each language from the «Was ist neu» lines, the build uploaded by the testflight skill, and the submission to App Review. Only when the user asks for an App Store release.
disable-model-invocation: true
---

# Publish a version on the App Store

The version on the App Store is the release in production: `vX.Y.Z` is
tagged and deployed (the `release` skill), and its «Was ist neu» line
(`news_X_Y_Z` in `web/messages/*.json`) becomes «Neuerungen» in each
language. `asc.py` talks to the App Store Connect API
(https://developer.apple.com/documentation/appstoreconnectapi) with the
same key as the upload: its key id and issuer id are in `CLAUDE.local.md`;
its file in `~/.appstoreconnect/private_keys/` is read by the script only,
never printed. Run it with `uv run` (it brings PyJWT):

```sh
export ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id>
uv run .claude/skills/app-store/asc.py status X.Y.Z
```

1. **The build:** uploaded by the `testflight` skill (its `upload.sh`).
   `status X.Y.Z` lists the builds of that version and their processing
   (`PROCESSING`, then `VALID`, 5–30 minutes after the upload).
2. **Prepare:** `prepare X.Y.Z` waits for the build to be `VALID` (45
   minutes at most), creates the App Store version (or takes the one not
   yet submitted), released after approval, sets «Neuerungen» in each
   language the App Store has (`de-DE` takes `de.json`, `en-US` and
   `en-GB` `en.json`, …) and chooses the build: the newest of that
   version, or `--build N`. Everything else (description, keywords,
   screenshots, privacy, age rating) App Store Connect copies from the
   last version; change it there.
   A language without a line stops it: add the line in
   `web/messages/*.json` (the release commit's job) and run it again.
   Another version still being prepared in App Store Connect (the
   API allows one) stops the creation: tell the user which.
3. **Show and ask:** `status X.Y.Z` shows the state, the chosen build and
   the texts. Show them to the user and ask with a question box before
   submitting: a submission goes to Apple and cannot be taken back here
   (only cancelled in App Store Connect while waiting for review).
4. **Submit:** `submit X.Y.Z` creates the review submission with the
   version and submits it: `WAITING_FOR_REVIEW`, then `IN_REVIEW`, then
   released by itself once approved. Report the state; Apple writes to
   the account's e-mail when it is approved or rejected, and a rejection
   is read in App Store Connect (Resolution Center).

Errors come back as App Store Connect's own `title: detail` (e.g. a
missing export compliance answer: `ITSAppUsesNonExemptEncryption` is
`false` in `Info.plist`, so it should not happen; a screenshot size
missing for a new device class). The key needs the role «App Manager».
