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
   afterwards); tags up to v1.7.1 carry the old export options, so give
   `-exportOptionsPlist` the path of `main`'s
   `app/ios/ExportOptions-upload.plist`.
2. **Archive** (about two minutes), in `app/`:
   ```sh
   FIREBASE_ANALYTICS_WITHOUT_ADID=true \
   flutter build ipa --build-name=$(git describe --tags --abbrev=0 | sed 's/^v//') \
     --build-number=$(git rev-list --count HEAD) \
     --dart-define=ALVYO_VERSION=$(git describe --tags --always)
   ```
   An error at the end while creating the IPA does not matter: the
   archive in `build/ios/archive/Runner.xcarchive` is what counts.
   `FIREBASE_ANALYTICS_WITHOUT_ADID` takes Google Analytics without the
   advertising id (no tracking prompt, App Store privacy labels). Check it
   before uploading; any output stops the release (`flutter clean`, build
   again):
   ```sh
   grep -rl AdSupport build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app
   ```
3. **Sign and upload**: signed on this Mac with the «Apple Distribution»
   certificate (in the keychain) and the App Store profile «Alvyo App
   Store» (`ios/ExportOptions-upload.plist`), uploaded with the App Store
   Connect API key («App Manager»; its file in
   `~/.appstoreconnect/private_keys/`, its key and issuer id in
   `CLAUDE.local.md`). Xcode's own Apple ID session is not used: the
   command line could not renew it.
   ```sh
   xcodebuild -exportArchive -archivePath build/ios/archive/Runner.xcarchive \
     -exportOptionsPlist ios/ExportOptions-upload.plist \
     -exportPath <scratchpad>/export \
     -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_<key id>.p8 \
     -authenticationKeyID <key id> -authenticationKeyIssuerID <issuer id>
   ```
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
4. **Report** the version and build number. «The bundle version must be
   higher» means that build number was uploaded already: a new commit (and
   release) gives the next one; do not change the number by hand.

Testers get the build after Apple's processing; a build for external
testers needs Beta App Review in App Store Connect the first time per
version, which the user does there.
