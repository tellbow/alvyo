import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'l10n/app_localizations.dart';
import 'screens/login_screen.dart';
import 'screens/routes_screen.dart';
import 'session.dart';

void main() => runApp(const OdysgehApp());

class OdysgehApp extends StatefulWidget {
  const OdysgehApp({super.key, this.session});
  final Session? session;

  @override
  State<OdysgehApp> createState() => _OdysgehAppState();
}

class _OdysgehAppState extends State<OdysgehApp> {
  late final Session _session = widget.session ?? Session();
  late final Future<Api?> _restored = _session.restore();
  Api? _api;
  bool _restoredOnce = false;

  Future<void> _logout() async {
    await _api?.logout().catchError((_) {});
    await _session.clear();
    setState(() => _api = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF047857), useMaterial3: true),
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
