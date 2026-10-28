#!/usr/bin/env bash
# Builds the app bundle (AAB) for Google Play from the checked-out release
# tag, signed with the key in app/android/key.properties (never read here),
# and checks what Google Play refuses or asks about. Usage: build.sh <out-dir>
set -euo pipefail

out=${1:?usage: build.sh <out-dir>}
repo=$(git rev-parse --show-toplevel)
cd "$repo/app"

test -f android/key.properties || { echo "app/android/key.properties is missing (android-install skill, «Once»)"; exit 1; }
tag=$(git describe --tags --exact-match)
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home

# Numbered like the release workflow's APK, so Play's build and the APK of
# the same release have the same version code.
flutter build appbundle --release \
  --build-name="${tag#v}" \
  --build-number="$(git rev-list --count HEAD)" \
  --dart-define=ALVYO_VERSION="$tag"
aab=build/app/outputs/bundle/release/app-release.aab

# No advertising id (as AdSupport on iOS): Firebase Analytics' manifest adds
# the permission unless AndroidManifest.xml removes it.
if unzip -p "$aab" base/manifest/AndroidManifest.xml | grep -aq 'permission.AD_ID'; then
  echo "the bundle asks for the advertising id (com.google.android.gms.permission.AD_ID): remove it in AndroidManifest.xml"
  exit 1
fi

# Every native library 16 KB aligned (Google Play requires it from 2027-02-01).
tmp=$(mktemp -d)
unzip -q "$aab" 'base/lib/arm64-v8a/*' -d "$tmp"
objdump=$(ls -d "$ANDROID_HOME"/ndk/*/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-objdump | tail -1)
for so in "$tmp"/base/lib/arm64-v8a/*.so; do
  if "$objdump" -p "$so" | awk '/LOAD/ { split($NF, a, "\\*\\*"); if (a[2] < 14) bad = 1 } END { exit !bad }'; then
    echo "$(basename "$so") is not 16 KB aligned"
    exit 1
  fi
done
rm -rf "$tmp"

mkdir -p "$out"
cp "$aab" "$out/alvyo-${tag#v}.aab"
echo "BUNDLE $out/alvyo-${tag#v}.aab, version code $(git rev-list --count HEAD)"
