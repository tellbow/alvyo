import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/bug_report.dart';
import 'package:alvyo/settings.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/main.dart';
import 'package:alvyo/session.dart';
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
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(); // the frame without the bug button, then the picture
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
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

  testWidgets('the screenshot is the window as shown, maps included, taken natively', (tester) async {
    // 1 × 1 pixel
    final window = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('alvyo/screenshot'),
      (call) async => call.method == 'window' ? window : null,
    );
    addTearDown(
      () =>
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('alvyo/screenshot'), null),
    );
    Map<String, dynamic>? sent;
    final api = Api(
      'https://alvyo.test',
      token: 't',
      client: MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response('{"id": "b1"}', 201, headers: {'content-type': 'application/json'});
      }),
    );
    await pump(tester, api, GlobalKey<NavigatorState>());
    await tester.tap(find.byKey(const Key('bug-open')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bug-text')), 'Die Karte fehlt im Bild.');
    await tester.pump();
    await tester.tap(find.byKey(const Key('bug-send')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(base64Decode(sent!['screenshot'] as String), window);
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

  testWidgets('the tab is dragged out of the way and stays there (feedback issue 56)', (tester) async {
    final api = Api('https://alvyo.test', token: 't', client: MockClient((req) async => http.Response('{}', 404)));
    addTearDown(() => AppSettings.instance.bugTabAt.value = 0.45);
    await pump(tester, api, GlobalKey<NavigatorState>());
    final tab = find.byKey(const Key('bug-open'));
    final before = tester.getTopLeft(tab).dy;
    await tester.drag(tab, const Offset(0, -100));
    await tester.pump();
    expect(tester.getTopLeft(tab).dy, lessThan(before - 50));
    expect(AppSettings.instance.bugTabAt.value, lessThan(0.45));

    // Android reports touches more often than it draws: several moves before
    // the next frame all count, the tab stays under the finger.
    final start = tester.getTopLeft(tab).dy;
    final finger = await tester.startGesture(tester.getCenter(tab));
    for (var i = 0; i < 12; i++) {
      await finger.moveBy(const Offset(0, 10));
    }
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await finger.moveBy(const Offset(0, 10));
    }
    await finger.up();
    await tester.pump();
    expect(tester.getTopLeft(tab).dy, closeTo(start + 240, 1));

    // Not off the screen.
    await tester.drag(tab, const Offset(0, 5000));
    await tester.pump();
    expect(
      tester.getBottomLeft(tab).dy,
      lessThanOrEqualTo(tester.view.physicalSize.height / tester.view.devicePixelRatio),
    );
  });
}

class _Saved extends Session {
  _Saved(this.api);
  final Api api;

  @override
  Future<Api?> restore() async => api;
}
