---
name: testflight
description: Builds the Alvyo iOS app of the last release tag and uploads it to App Store Connect for TestFlight, signed on this Mac (Apple Distribution certificate, App Store profile «Alvyo App Store») and uploaded with an App Store Connect API key, without the user. Only when the user asks for a TestFlight or App Store build.
disable-model-invocation: true
---

# Upload a build to TestFlight

An upload goes to Apple and cannot be taken back; a build number counts
only once. Build from a release tag (the `release` skill), so the version
in TestFlight is the one in production.

1. **On the tag:** `git describe --tags --exact-match` names the release
   (`vX.Y.Z`) and `git status` is clean. When `main` has moved on since
   the tag, build in a worktree of it instead
   (`git worktree add --detach <scratchpad>/rel-X.Y.Z vX.Y.Z`, removed
   afterwards, and run `main`'s `upload.sh` there); tags up to v1.7.1
   carry the old export options, so give it the path of `main`'s
   `app/ios/ExportOptions-upload.plist` as second argument.
2. **Build and upload** (about four minutes), from the checkout of the tag,
   with the key id and issuer id from `CLAUDE.local.md` (the key's file in
   `~/.appstoreconnect/private_keys/` is never read or printed):
   ```sh
   ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id> \
     .claude/skills/testflight/upload.sh <scratchpad>/export [<main's app/ios/ExportOptions-upload.plist>]
   ```
   It archives with the tag's version and the commit count as build
   number, stops if the archive has AdSupport (Google Analytics must come
   without the advertising id: no tracking prompt, App Store privacy
   labels), and signs on this Mac with the «Apple Distribution»
   certificate (in the keychain) and the App Store profile «Alvyo App
   Store» (`ios/ExportOptions-upload.plist`), uploaded with the App Store
   Connect API key («App Manager»). Xcode's own Apple ID session is not
   used: the command line could not renew it. The error while creating
   the IPA after the archive does not matter.
   The Apple Watch app inside (`ios/AlvyoWatch`) is signed with its own
   profile «Alvyo Watch App Store» (App ID `ch.tellbow.alvyo.watchkitapp`).
   «Provisioning profile … not found» or «expired»: the profiles are renewed
   once a year in the developer portal (Profiles → «Alvyo App Store» or
   «Alvyo Watch App Store» → Edit → Generate; download and double-click),
   by the user.
   «Upload succeeded» and «EXPORT SUCCEEDED» mean it is in App Store
   Connect, processing (5–30 minutes until TestFlight shows it). The
   warning that MapLibre.framework has no dSYM is harmless: only crashes
   inside MapLibre stay unsymbolicated.
3. **Report** the version and build number. «The bundle version must be
   higher» means that build number was uploaded already: a new commit (and
   release) gives the next one; do not change the number by hand.

Testers get the build after Apple's processing; a build for external
testers needs Beta App Review in App Store Connect the first time per
version, which the user does there. For the App Store itself (the
version, «Neuerungen», this build, App Review): the `app-store` skill.
