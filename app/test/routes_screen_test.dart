import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/navigation/tracker.dart';
import 'package:alvyo/screens/record_screen.dart';
import 'package:alvyo/screens/route_screen.dart';
import 'package:alvyo/screens/routes_screen.dart';
import 'package:alvyo/theme.dart';

void main() {
  late Directory support;
  setUpAll(() {
    support = Directory.systemTemp.createTempSync('support');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => support.path,
    );
  });
  tearDownAll(() => support.deleteSync(recursive: true));

  final hikes = <Map<String, dynamic>>[];
  final client = MockClient((req) async {
    if (req.url.path == '/api/v1/hikes') {
      hikes.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response(jsonEncode({'id': 'route-9'}), 201, headers: {'content-type': 'application/json'});
    }
    final body = switch (req.url.path) {
      '/api/v1/routes' => {'routes': <Object>[]},
      '/api/v1/journeys' => {'journeys': <Object>[]},
      '/api/v1/feed' => {'items': <Object>[]},
      '/api/v1/shared' => {'routes': <Object>[], 'journeys': <Object>[], 'collections': <Object>[]},
      '/api/v1/me' => {'id': 'u1', 'username': 'wodan', 'display_name': 'Wodan', 'speed_factor': 1},
      _ => null,
    };
    if (body == null) return http.Response('', 404);
    return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
  });

  Future<void> until(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 100 && f.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pump(
    WidgetTester tester,
    Brightness brightness,
    VoidCallback onLogout, {
    Widget Function(Api api)? record,
  }) async {
    final api = Api('https://alvyo.test', token: 't', client: client);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        theme: alvyoTheme(brightness),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: RoutesScreen(api: api, onLogout: onLogout, record: record == null ? null : () => record(api)),
      ),
    );
    await until(tester, find.text('Noch keine Routen. Plane sie auf der Website.'));
  }

  for (final brightness in Brightness.values) {
    testWidgets('the bar: journeys, the feed and the profile ($brightness)', (tester) async {
      var loggedOut = false;
      await pump(tester, brightness, () => loggedOut = true);
      expect(find.text('Meine Routen'), findsOneWidget);
      // Named under their icons, shorter than the titles.
      for (final name in ['Routen', 'Etappen', 'Neuigkeiten', 'Profil']) {
        expect(find.text(name), findsOneWidget);
      }

      await tester.tap(find.byKey(const Key('tab-journeys')));
      await until(tester, find.text('Etappentouren'));
      expect(find.text('Etappentouren'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tab-feed')));
      await until(tester, find.byKey(const Key('feed-empty')));
      expect(find.byKey(const Key('feed-empty')), findsOneWidget);

      await tester.tap(find.byKey(const Key('tab-profile')));
      await until(tester, find.text('@wodan'));
      expect(find.text('Wodan'), findsOneWidget);
      expect(find.text('Server: alvyo.test'), findsOneWidget);
      // Clear of the floating bar.
      final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.byKey(const Key('logout')), 200, scrollable: list);
      await tester.drag(list, const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logout')));
      expect(loggedOut, isTrue);
    });
  }

  testWidgets('the record button records a hike without a route, which becomes one', (tester) async {
    final positions = StreamController<Fix>();
    Fix at(int i) => Fix(lon: 8, lat: 46.5 + i * 0.001, accuracyM: 5, time: DateTime.now().toUtc());
    await pump(
      tester,
      Brightness.light,
      () {},
      record: (api) => RecordScreen(api: api, positions: () => positions.stream, map: const SizedBox.expand()),
    );

    await tester.tap(find.byKey(const Key('record')));
    await until(tester, find.byKey(const Key('record-start')));
    expect(find.text('Warte auf GPS …'), findsOneWidget);
    positions.add(at(0)); // shown before the start, and where the hike starts
    await until(tester, find.text('Aufzeichnung starten'));
    await tester.tap(find.byKey(const Key('record-start')));
    await until(tester, find.byKey(const Key('record-progress')));
    positions
      ..add(at(1))
      ..add(at(2));
    await until(tester, find.text('223\u00a0m'));
    expect(find.text('223\u00a0m'), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-finish')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-finish-confirm')));
    await until(tester, find.byType(RouteScreen));
    expect(hikes.single.containsKey('route_id'), isFalse);
    expect(hikes.single['title'], startsWith('Wanderung, '));
    expect(hikes.single['points'], hasLength(3));
    final saved = find.textContaining('Gespeichert unter «Meine Routen»: 223\u00a0m');
    await until(tester, saved);
    expect(saved, findsOneWidget);
    unawaited(positions.close());
  });
}
