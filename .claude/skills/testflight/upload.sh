#!/bin/zsh
# Builds the iOS app of the release tag checked out and uploads it to App
# Store Connect (TestFlight, and the build an App Store version takes).
# Usage, in a checkout of the tag:
#   ASC_KEY_ID=… ASC_ISSUER_ID=… .claude/skills/testflight/upload.sh <export dir> [<export options plist>]
# The key file is ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8.
set -eu

out=${1:?export directory}
cd "$(git rev-parse --show-toplevel)/app"
options=${2:-$PWD/ios/ExportOptions-upload.plist}

tag=$(git describe --tags --exact-match)
if [[ -n $(git status --porcelain) ]]; then
  echo "uncommitted changes: build from the tag only" >&2
  exit 1
fi

# Google Analytics without the advertising id (no tracking prompt, App
# Store privacy labels). The error at the end, creating the IPA, does not
# matter: the archive is what is signed below.
FIREBASE_ANALYTICS_WITHOUT_ADID=true flutter build ipa \
  --build-name=${tag#v} --build-number=$(git rev-list --count HEAD) \
  --dart-define=ALVYO_VERSION=$tag || true
archive=build/ios/archive/Runner.xcarchive
if [[ ! -d $archive ]]; then
  echo "no archive" >&2
  exit 1
fi
if grep -rl AdSupport $archive/Products/Applications/Runner.app; then
  echo "AdSupport in the app: flutter clean and build again" >&2
  exit 1
fi

xcodebuild -exportArchive -archivePath $archive -exportOptionsPlist "$options" -exportPath "$out" \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8 \
  -authenticationKeyID $ASC_KEY_ID -authenticationKeyIssuerID $ASC_ISSUER_ID
echo "uploaded ${tag#v} build $(git rev-list --count HEAD)"
