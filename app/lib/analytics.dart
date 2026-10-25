import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'firebase_options.dart';

/// Where screen views go: Google Analytics, or a fake in tests.
abstract interface class AnalyticsSink {
  /// Switches collection on or off; off also forgets the app's analytics id.
  Future<void> collect(bool on);
  Future<void> screen(String name);
}

/// Google Analytics through Firebase, on the website's property. Nothing
/// is sent until the user agrees: collection starts switched off
/// (Info.plist, AndroidManifest.xml), and without the advertising id.
class _Firebase implements AnalyticsSink {
  final _ga = FirebaseAnalytics.instance;

  @override
  Future<void> collect(bool on) async {
    await _ga.setConsent(
      analyticsStorageConsentGranted: on,
      adStorageConsentGranted: false,
      adUserDataConsentGranted: false,
      adPersonalizationSignalsConsentGranted: false,
    );
    await _ga.setAnalyticsCollectionEnabled(on);
    if (!on) await _ga.resetAnalyticsData();
  }

  @override
  Future<void> screen(String name) => _ga.logScreenView(screenName: name, screenClass: name);
}

/// Statistics as on the website (requirement 62, feedback issues 6 and 7):
/// which screens are opened, named by their kind ("route", "journey"),
/// never with titles, ids or links. Only in release builds that have the
/// Firebase settings, and only after «Akzeptieren»; the choice is kept in
/// the Keychain like the other settings.
class Analytics {
  Analytics({FlutterSecureStorage? storage, this._sink}) : _storage = storage ?? const FlutterSecureStorage();

  static final instance = Analytics();

  final FlutterSecureStorage _storage;
  AnalyticsSink? _sink;

  /// The user's choice; null until asked.
  final consent = ValueNotifier<bool?>(null);

  late final Future<void> loaded = _load();

  /// Whether this build measures at all: asked for consent and shown in
  /// the settings only then.
  bool get active => _sink != null;

  Future<void> _load() async {
    try {
      consent.value = switch (await _storage.read(key: 'analytics')) {
        'granted' => true,
        'denied' => false,
        _ => null,
      };
    } on Object {
      // no Keychain (tests): not asked yet
    }
    if (_sink == null && kReleaseMode) {
      if (DefaultFirebaseOptions.currentPlatform case final options?) {
        try {
          await Firebase.initializeApp(options: options);
          _sink = _Firebase();
        } on Object {
          // without statistics
        }
      }
    }
    if (consent.value == true) await _sink?.collect(true).catchError((_) {});
  }

  Future<void> setConsent(bool granted) async {
    consent.value = granted;
    try {
      await _storage.write(key: 'analytics', value: granted ? 'granted' : 'denied');
    } on Object {
      // asked again at the next start
    }
    await _sink?.collect(granted).catchError((_) {});
  }

  /// A screen of the kind [name] was opened.
  void screen(String name) {
    if (consent.value == true) _sink?.screen(name).catchError((_) {});
  }
}
