import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/bug_report.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/main.dart';
import 'package:alvyo/session.dart';
import 'package:alvyo/settings.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  Future<void> pump(WidgetTester tester, Api? api, GlobalKey<NavigatorState> nav) => tester.pumpWidget(
    MaterialApp(
      navigatorKey: nav,
      locale: const Locale('de'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => BugReportFrame(api: () => api, navigator: nav, child: child!),
      home: const Scaffold(body: Center(child: Text('Meine Routen'))),
    ),
  );

  testWidgets('a bug reported from the screen that is open, with a screenshot', (tester) async {
    Map<String, dynamic>? sent;
    final api = Api(
      'https://alvyo.test',
      token: 't',
      client: MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response('{"id": "b1"}', 201, headers: {'content-type': 'application/json'});
      }),
    );
    openPlaces.add('/routes/r1');
    addTearDown(openPlaces.clear);
    await pump(tester, api, GlobalKey<NavigatorState>());
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('bug-open')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bug-with-shot')), findsOneWidget);
    expect(find.textContaining('das nur das Alvyo-Team sieht: dein Text, die Adresse (/routes/r1)'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('bug-text')), 'Die Karte bleibt leer.');
    await tester.pump();
    await tester.tap(find.byKey(const Key('bug-send')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bug-sent')), findsOneWidget);
    expect(sent!['description'], 'Die Karte bleibt leer.');
    expect(sent!['place'], '/routes/r1');
    expect(sent!['platform'], 'android'); // widget tests run as Android
    expect(sent!['version'], 'dev');
    expect(base64Decode(sent!['screenshot'] as String).sublist(1, 4), 'PNG'.codeUnits);
  });

  testWidgets('not before signing in', (tester) async {
    await pump(tester, null, GlobalKey<NavigatorState>());
    expect(find.byKey(const Key('bug-open')), findsNothing);
  });

  // Started with a saved login: the tab is there without logging in again.
  testWidgets('with a saved session, from the start', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = Api(
      'https://alvyo.test',
      token: 't',
      client: MockClient((_) async => http.Response('{}', 404, headers: {'content-type': 'application/json'})),
    );
    await tester.pumpWidget(AlvyoApp(session: _Saved(api), settings: AppSettings()));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('bug-open')), findsOneWidget);
  });
}

class _Saved extends Session {
  _Saved(this.api);
  final Api api;

  @override
  Future<Api?> restore() async => api;
}
