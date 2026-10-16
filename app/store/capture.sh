#!/usr/bin/env bash
# Captures the app's states for the App Store on an iPhone 17 Pro simulator
# (1206 × 2622) into work/raw/<language>/ and on an iPad Pro 13-inch one
# (2064 × 2752) into work/raw-ipad/<language>/: in the simulator's language,
# 9:41, location Grindelwald. Puts the simulators back in English
# afterwards (the integration tests expect it).
# Usage: capture.sh [de,en,fr,it] [state,state…] [iphone,ipad]  (the states of screenshots_test.dart)
set -euo pipefail

store=$(cd "$(dirname "$0")" && pwd)
app=$(dirname "$store")
simulator() { xcrun simctl list devices available | grep -m1 "$1 (" | grep -oE '[0-9A-F-]{36}'; }
langs=${1:-de,en,fr,it}
states=${2:-route,nav,reach,journey,weather,discover}
devices=${3:-iphone,ipad}
used=()

language() { # simulator, language: the language first, then the others
  local order=("$2")
  for l in de en fr it; do [ "$l" != "$2" ] && order+=("$l"); done
  xcrun simctl bootstatus "$1" -b >/dev/null # its settings are written while it runs
  xcrun simctl spawn "$1" defaults write -g AppleLanguages -array "${order[@]/%/-CH}"
  xcrun simctl spawn "$1" defaults write -g AppleLocale "$2_CH"
  xcrun simctl shutdown "$1" 2>/dev/null || true
  xcrun simctl boot "$1"
  xcrun simctl bootstatus "$1" -b >/dev/null
}
cleanup() {
  rm -f "$app/integration_test/store_screenshots_test.dart"
  for id in ${used[@]+"${used[@]}"}; do
    xcrun simctl status_bar "$id" clear
    language "$id" en
  done
}
trap cleanup EXIT

cp "$store/screenshots_test.dart" "$app/integration_test/store_screenshots_test.dart"
for device in ${devices//,/ }; do
  case $device in
    iphone) id=${SIMULATOR_ID:-$(simulator 'iPhone 17 Pro')} raw=$store/work/raw ;;
    ipad) id=${IPAD_SIMULATOR_ID:-$(simulator 'iPad Pro 13-inch (M5)')} raw=$store/work/raw-ipad ;;
    *) echo "unknown device $device (iphone or ipad)" >&2; exit 1 ;;
  esac
  used+=("$id")
  for lang in ${langs//,/ }; do
    echo "== $device $lang"
    mkdir -p "$raw/$lang"
    language "$id" "$lang"
    xcrun simctl keychain "$id" reset # logged out, and the app follows the simulator's language
    xcrun simctl status_bar "$id" override --time 9:41 --batteryState discharging --batteryLevel 100 \
      --cellularMode active --cellularBars 4 --wifiBars 3 --dataNetwork wifi --operatorName ''
    xcrun simctl location "$id" set 46.6244,8.0413
    (cd "$app" && flutter test integration_test/store_screenshots_test.dart -d "$id" \
      --dart-define=SHOTS="$states" --dart-define=LANG="$lang" 2>&1) |
      while IFS= read -r line; do
        case "$line" in
          *"SHOT "*)
            name=${line##*SHOT }
            sleep 2
            xcrun simctl io "$id" screenshot "$raw/$lang/$name.png" >/dev/null 2>&1
            echo "captured $device/$lang/$name"
            ;;
          *"timed out"* | *"failed"* | *"passed"*) echo "$line" ;;
        esac
      done
  done
done
