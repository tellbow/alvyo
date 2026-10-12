#!/usr/bin/env bash
# Captures the app's states for the App Store on an iPhone 17 Pro simulator
# (1206 × 2622) into work/raw/<language>/: in the simulator's language,
# 9:41, location Grindelwald. Puts the simulator back in English afterwards
# (the integration tests expect it).
# Usage: capture.sh [de,en,fr,it] [state,state…]  (the states of screenshots_test.dart)
set -euo pipefail

store=$(cd "$(dirname "$0")" && pwd)
app=$(dirname "$store")
id=${SIMULATOR_ID:-$(xcrun simctl list devices available | grep -m1 'iPhone 17 Pro (' | grep -oE '[0-9A-F-]{36}')}
langs=${1:-de,en,fr,it}
states=${2:-route,nav,reach,journey,weather,discover}

language() { # the language first, then the others
  local order=("$1")
  for l in de en fr it; do [ "$l" != "$1" ] && order+=("$l"); done
  xcrun simctl spawn "$id" defaults write -g AppleLanguages -array "${order[@]/%/-CH}"
  xcrun simctl spawn "$id" defaults write -g AppleLocale "$1_CH"
  xcrun simctl shutdown "$id" 2>/dev/null || true
  xcrun simctl boot "$id"
  xcrun simctl bootstatus "$id" -b >/dev/null
}
cleanup() {
  rm -f "$app/integration_test/store_screenshots_test.dart"
  xcrun simctl status_bar "$id" clear
  language en
}
trap cleanup EXIT

cp "$store/screenshots_test.dart" "$app/integration_test/store_screenshots_test.dart"
for lang in ${langs//,/ }; do
  echo "== $lang"
  mkdir -p "$store/work/raw/$lang"
  language "$lang"
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
          xcrun simctl io "$id" screenshot "$store/work/raw/$lang/$name.png" >/dev/null 2>&1
          echo "captured $lang/$name"
          ;;
        *"timed out"* | *"failed"* | *"passed"*) echo "$line" ;;
      esac
    done
done
