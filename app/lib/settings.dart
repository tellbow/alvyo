import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'l10n/app_localizations.dart';

/// Light or dark and the language: the phone's unless chosen in the
/// profile, remembered in the Keychain like the session.
class AppSettings {
  AppSettings({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static final instance = AppSettings();

  final FlutterSecureStorage _storage;
  final theme = ValueNotifier(ThemeMode.system);

  /// null: the phone's language.
  final locale = ValueNotifier<Locale?>(null);
  late final Future<void> loaded = _load();

  Future<void> _load() async {
    try {
      final t = await _storage.read(key: 'theme');
      theme.value = ThemeMode.values.firstWhere((m) => m.name == t, orElse: () => ThemeMode.system);
      final l = await _storage.read(key: 'locale');
      locale.value = AppLocalizations.supportedLocales.where((s) => s.languageCode == l).firstOrNull;
    } on Object {
      // no Keychain (tests): the phone's
    }
  }

  Future<void> setTheme(ThemeMode m) async {
    theme.value = m;
    await _write('theme', m == ThemeMode.system ? null : m.name);
  }

  Future<void> setLocale(Locale? l) async {
    locale.value = l;
    await _write('locale', l?.languageCode);
  }

  Future<void> _write(String key, String? value) async {
    try {
      value == null ? await _storage.delete(key: key) : await _storage.write(key: key, value: value);
    } on Object {
      // not remembered, still switched
    }
  }
}
