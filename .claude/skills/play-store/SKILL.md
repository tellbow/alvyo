---
name: play-store
description: Publishes a release of the Alvyo Android app on Google Play through the Google Play Developer API - builds the app bundle (AAB) of the release tag, uploads it to a track (internal testing first) with the «Was ist neu» lines as release notes, and promotes it to production. Only when the user asks for a Play Store release.
disable-model-invocation: true
---

# Publish a version on Google Play

The version on Google Play is the release in production: `vX.Y.Z` is
tagged and deployed (the `release` skill), and its «Was ist neu» line
(`news_X_Y_Z` in `web/messages/*.json`) becomes the release notes in each
language of the store listing (500 characters at most). `play.py` talks to
the Google Play Developer API
(https://developers.google.com/android-publisher) as a service account;
its key file (`~/.google-play/alvyo-publisher.json`, or `PLAY_KEY_FILE`)
is read by the script only, never printed. Run it with `uv run` (it brings
PyJWT). An upload and a commit go to Google and cannot be taken back; a
version code counts only once.

1. **On the tag:** `git describe --tags --exact-match` names the release
   (`vX.Y.Z`) and `git status` is clean. When `main` has moved on since
   the tag, build in a worktree of it instead
   (`git worktree add --detach <scratchpad>/rel-X.Y.Z vX.Y.Z`, removed
   afterwards, and run `main`'s `build.sh` there).
2. **Build** (about two minutes):
   `.claude/skills/play-store/build.sh <scratchpad>/play`. It builds the
   bundle with the tag's version and the commit count as version code
   (as the release workflow's APK), signed with the key in
   `app/android/key.properties` (never read or printed), and stops if the
   bundle asks for the advertising id or a native library is not 16 KB
   aligned. It prints `BUNDLE <path>, version code N`.
3. **Internal testing:**
   `uv run .claude/skills/play-store/play.py upload X.Y.Z <path>` uploads
   it to the track `internal` with the release notes and commits. Testers
   on that track get it within minutes, without review.
   «Only releases with status draft may be created on draft app»: the app
   has never been published; run it again with `--draft` and tell the user
   to roll it out in Play Console (Testing → Internal testing), once.
   «Version code N has already been used»: that build is on Google Play
   already; `status` shows where.
4. **Show and ask:** `status` lists each track's releases. Show them and
   the release notes to the user and ask with a question box before
   promoting: production goes to Google's review and then to everyone.
5. **Production:** `promote X.Y.Z --to production` puts the same build
   (no new upload) on production with the notes and commits; Google
   reviews it (hours to a few days) and publishes it by itself. Report
   the state; a rejection is read in Play Console (Policy status) and in
   the account's e-mail.

The store listing (texts, screenshots), the «App content» declarations
(data safety, content rating, foreground service, …) and the countries are
kept in Play Console; a release copies them. Errors come back as Google's
own message; «The caller does not have permission»: the service account
lacks the app's release permissions in Play Console (Users and
permissions).

## Once (the user does this)

The first release, the listing, the app content forms and the closed test
(a personal account: 12 testers for 14 days before production):
`app/store/google-play.md`. For the API besides:

- In a Google Cloud project of the account's owner, enable the «Google
  Play Android Developer API», create a service account and a JSON key
  for it, saved as `~/.google-play/alvyo-publisher.json` (`chmod 600`).
- Play Console › Nutzer und Berechtigungen › «Neue Nutzer einladen»: its
  e-mail, with access to Alvyo and the permissions to release to testing
  tracks and to production and to manage testing tracks. It can take up
  to a day before the API accepts it.
