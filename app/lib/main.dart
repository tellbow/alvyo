import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'l10n/app_localizations.dart';
import 'screens/login_screen.dart';
import 'screens/routes_screen.dart';
import 'session.dart';
import 'theme.dart';

void main() => runApp(const AlvyoApp());

class AlvyoApp extends StatefulWidget {
  const AlvyoApp({super.key, this.session});
  final Session? session;

  @override
  State<AlvyoApp> createState() => _AlvyoAppState();
}

class _AlvyoAppState extends State<AlvyoApp> {
  late final Session _session = widget.session ?? Session();
  late final Future<Api?> _restored = _session.restore();
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
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: alvyoTheme(Brightness.light),
      darkTheme: alvyoTheme(Brightness.dark),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
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
          return RoutesScreen(api: api, onLogout: _logout);
        },
      ),
    );
  }
}
