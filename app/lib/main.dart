import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'l10n/app_localizations.dart';
import 'screens/login_screen.dart';
import 'screens/routes_screen.dart';
import 'session.dart';
import 'settings.dart';
import 'theme.dart';

void main() => runApp(const AlvyoApp());

class AlvyoApp extends StatefulWidget {
  const AlvyoApp({super.key, this.session, this.settings});
  final Session? session;
  final AppSettings? settings;

  @override
  State<AlvyoApp> createState() => _AlvyoAppState();
}

class _AlvyoAppState extends State<AlvyoApp> {
  late final Session _session = widget.session ?? Session();
  late final AppSettings _settings = widget.settings ?? AppSettings.instance;
  // The settings first, so the first screen is in the chosen look.
  late final Future<Api?> _restored = _settings.loaded.then((_) => _session.restore());
  Api? _api;
  bool _restoredOnce = false;

  Future<void> _logout() async {
    await _api?.logout().catchError((_) {});
    await _session.clear();
    setState(() => _api = null);
  }

  /// A session saved before the account was kept with it learns the
  /// account once online.
  void _learnUser(Api? api) {
    if (api == null || api.userId != null) return;
    api
        .me()
        .then((m) async {
          api.userId = m.id;
          await _session.save(api);
        })
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_settings.theme, _settings.locale]),
    builder: (context, _) => _app(context),
  );

  Widget _app(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: alvyoTheme(Brightness.light),
      darkTheme: alvyoTheme(Brightness.dark),
      themeMode: _settings.theme.value,
      locale: _settings.locale.value,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      // Numbers in the app's language («19,3 km» in French, format.dart).
      builder: (context, child) {
        Intl.defaultLocale = Localizations.localeOf(context).languageCode;
        return child!;
      },
      home: FutureBuilder(
        future: _restored,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (!_restoredOnce) {
            _api = snap.data;
            _restoredOnce = true;
            _learnUser(_api);
          }
          final api = _api;
          if (api == null) {
            return LoginScreen(session: _session, onLoggedIn: (a) => setState(() => _api = a));
          }
          return RoutesScreen(api: api, onLogout: _logout, settings: _settings);
        },
      ),
    );
  }
}
