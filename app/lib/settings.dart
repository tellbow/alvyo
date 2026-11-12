import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'format.dart';
import 'l10n/app_localizations.dart';

/// Light or dark and the language: the phone's unless chosen in the
/// profile, remembered in the Keychain like the session; and the pace.
class AppSettings {
  AppSettings({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static final instance = AppSettings();

  final FlutterSecureStorage _storage;
  final theme = ValueNotifier(ThemeMode.system);

  /// null: the phone's language.
  final locale = ValueNotifier<Locale?>(null);

  /// Apple Watch hikes are imported when the app opens: those since then;
  /// null: off.
  final watchAutoSince = ValueNotifier<DateTime?>(null);

  /// How far down the screen the bug-report tab is, 0 to 1; dragged away
  /// from what it covers (feedback issue 56).
  final bugTabAt = ValueNotifier<double>(0.45);

  /// The planner's «So geht's» hidden (feedback issue 88).
  final plannerHelpHidden = ValueNotifier(false);
  late final Future<void> loaded = _load();

  Future<void> _load() async {
    try {
      final t = await _storage.read(key: 'theme');
      theme.value = ThemeMode.values.firstWhere((m) => m.name == t, orElse: () => ThemeMode.system);
      final l = await _storage.read(key: 'locale');
      locale.value = AppLocalizations.supportedLocales.where((s) => s.languageCode == l).firstOrNull;
      watchAutoSince.value = DateTime.tryParse(await _storage.read(key: 'watch-auto') ?? '');
      if (double.tryParse(await _storage.read(key: 'bug-tab') ?? '') case final at?) bugTabAt.value = at;
      plannerHelpHidden.value = await _storage.read(key: 'planner-help') == 'hidden';
      // The account's pace as last known, for hikes started offline.
      if (double.tryParse(await _storage.read(key: 'pace') ?? '') case final pace?) hikerPace.value = pace;
    } on Object {
      // no Keychain (tests): the phone's
    }
    hikerPace.addListener(() => _write('pace', hikerPace.value == 1 ? null : '${hikerPace.value}'));
  }

  Future<void> setTheme(ThemeMode m) async {
    theme.value = m;
    await _write('theme', m == ThemeMode.system ? null : m.name);
  }

  Future<void> setLocale(Locale? l) async {
    locale.value = l;
    await _write('locale', l?.languageCode);
  }

  Future<void> setPlannerHelpHidden(bool hidden) async {
    plannerHelpHidden.value = hidden;
    await _write('planner-help', hidden ? 'hidden' : null);
  }

  Future<void> saveBugTab() => _write('bug-tab', '${bugTabAt.value}');

  /// Switches the import of new Apple Watch hikes on (from now) or off.
  Future<void> setWatchAuto(bool on) async {
    watchAutoSince.value = on ? DateTime.now() : null;
    await _write('watch-auto', watchAutoSince.value?.toIso8601String());
  }

  Future<void> _write(String key, String? value) async {
    try {
      value == null ? await _storage.delete(key: key) : await _storage.write(key: key, value: value);
    } on Object {
      // not remembered, still switched
    }
  }
}
