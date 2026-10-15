---
name: testflight
description: Builds the Alvyo iOS app of the last release tag and uploads it to App Store Connect for TestFlight, signed through the Apple ID in Xcode. Only when the user asks for a TestFlight or App Store build.
disable-model-invocation: true
---

# Upload a build to TestFlight

An upload goes to Apple and cannot be taken back; a build number counts
only once. Build from a release tag (the `release` skill), so the version
in TestFlight is the one in production.

1. **On the tag:** `git describe --tags --exact-match` names the release
   (`vX.Y.Z`) and `git status` is clean. Otherwise stop and say so.
2. **Archive** (about two minutes), in `app/`:
   ```sh
   flutter build ipa --build-name=$(git describe --tags --abbrev=0 | sed 's/^v//') \
     --build-number=$(git rev-list --count HEAD) \
     --dart-define=ALVYO_VERSION=$(git describe --tags --always)
   ```
   It ends with «Encountered error while creating the IPA: … No signing
   certificate "iOS Distribution" found»: expected, there is no
   distribution certificate on this Mac. The archive in
   `build/ios/archive/Runner.xcarchive` is what counts.
3. **Sign and upload** with Xcode's cloud signing (the Apple ID in Xcode →
   Settings → Accounts, team HYFKN2HQXF), as the Organizer does:
   ```sh
   xcodebuild -exportArchive -archivePath build/ios/archive/Runner.xcarchive \
     -exportOptionsPlist ios/ExportOptions-upload.plist \
     -exportPath <scratchpad>/export -allowProvisioningUpdates
   ```
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
