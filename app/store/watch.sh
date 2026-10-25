#!/usr/bin/env bash
# The Apple Watch pictures for the App Store (Apple Watch Series 12 46 mm,
# 416 × 496) into <language>/watch/: the tours, a hike on the «Eiger Trail»
# with its next turn, its whole route, and the controls. The watch app's UI
# test (testStoreScreenshots) shows watch-state.mjs's state with a made-up
# phone. Needs the dev stack, the API, the web dev server and seed.sh's
# account (for the state only). The clock shows the Mac's time: watchOS
# simulators take no status bar override.
# Usage: watch.sh [de,en,fr,it]
set -euo pipefail

store=$(cd "$(dirname "$0")" && pwd)
ios=$(dirname "$store")/ios
work=$store/work/watch
langs=${1:-de,en,fr,it}
id=${WATCH_SIMULATOR_ID:-$(xcrun simctl list devices available | grep -m1 'Apple Watch Series 12 (46mm) (' | grep -oE '[0-9A-F-]{36}')}
mkdir -p "$work"

bun "$store/watch-state.mjs" >"$work/state.json"
xcrun simctl boot "$id" 2>/dev/null || true
xcrun simctl bootstatus "$id" -b >/dev/null
(cd "$ios" && xcodebuild build-for-testing -quiet -project Runner.xcodeproj -scheme AlvyoWatch \
  -destination "platform=watchOS Simulator,id=$id" -derivedDataPath "$work/build")

for lang in ${langs//,/ }; do
  echo "== watch $lang"
  rm -rf "$work/$lang.xcresult" "$work/$lang"
  (cd "$ios" && TEST_RUNNER_ALVYO_STORE="$work/state.json" TEST_RUNNER_ALVYO_LANG="$lang" \
    xcodebuild test-without-building -quiet -project Runner.xcodeproj -scheme AlvyoWatch \
    -destination "platform=watchOS Simulator,id=$id" -derivedDataPath "$work/build" \
    -only-testing:AlvyoWatchUITests/AlvyoWatchUITests/testStoreScreenshots \
    -resultBundlePath "$work/$lang.xcresult")
  xcrun xcresulttool export attachments --path "$work/$lang.xcresult" --output-path "$work/$lang" >/dev/null
  mkdir -p "$store/$lang/watch"
  # The attachments by the names the test gave them.
  python3 -I - "$work/$lang" "$store/$lang/watch" <<'EOF'
import json, shutil, sys
src, dst = sys.argv[1], sys.argv[2]
for test in json.load(open(f"{src}/manifest.json")):
    for a in test["attachments"]:
        name = a["suggestedHumanReadableName"].split("_")[0]
        shutil.copy(f"{src}/{a['exportedFileName']}", f"{dst}/{name}.png")
        print(f"  {dst}/{name}.png")
EOF
done
