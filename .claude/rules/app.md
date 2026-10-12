---
paths:
  - "app/**"
---

# Flutter app (iOS and Android)

- Plugins come through Swift Package Manager only; plugins that need
  CocoaPods are out (flutter_tts was dropped for that). Small native pieces
  are method channels in `ios/Runner/AppDelegate.swift` (`alvyo/backup`,
  `alvyo/speech`) and, for Android, in
  `android/app/src/main/kotlin/ch/tellbow/alvyo/MainActivity.kt`
  (`alvyo/speech`; backups by `res/xml/*_rules.xml`). Something only one
  platform has yet is hidden on the other with `Platform.isAndroid`
  (`dart:io`; widget tests run as neither).
- `dart format` with page width 120, flutter_lints.
- Texts in `lib/l10n/app_*.arb` (`app_de.arb` is the template and holds the
  placeholders); run `flutter gen-l10n`; the generated files are committed.
- After an `await`, check `mounted` before `setState` or using the context.
- Files: offline maps and saved journeys in `PackStore` (`lib/offline/`),
  written to a temporary file and renamed. A recording is an append-only
  JSONL file; writes go one after the other and a cut-off last line is
  skipped (`lib/navigation/recording.dart`).
- Tests in `test/`: the API through `MockClient` (declare UTF-8 in test
  answers with non-ASCII text); for `PackStore.open`, mock the
  `plugins.flutter.io/path_provider` channel; real file work in widget tests
  needs `tester.runAsync`. Integration tests in `integration_test/` run on
  the simulator against the local dev stack (skill `app-simulator-tests`).
- The app talks to production (https://alvyo.tellbow.ch) unless the login
  names another server (a debug build only: release builds have no server
  field); features that need new API endpoints work there only
  after a release.
