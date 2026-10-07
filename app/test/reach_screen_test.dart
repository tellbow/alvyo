import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/screens/reach_screen.dart';

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

List<List<List<double>>> _square(double r) => [
  [
    [9.4 - r, 47 - r],
    [9.4 + r, 47 - r],
    [9.4 + r, 47 + r],
    [9.4 - r, 47 - r],
  ],
];

void main() {
  // A start found by name: the areas of 2, 4 and 8 hours there and back;
  // one way; then alpine ways; a point without a path says so.
  testWidgets('how far one gets from a place', (tester) async {
    // A tall phone: the panel shows all it holds.
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final asked = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      return switch ((req.method, req.url.path)) {
        ('GET', '/api/v1/me') => _json({'id': 'u1', 'username': 'anna', 'display_name': 'Anna', 'speed_factor': 1.5}),
        ('GET', '/api/v1/places/search') => _json({
          'places': [
            {
              'name': 'Sargans',
              'kind': 'pt_stop',
              'detail': 'Bahnhof',
              'at': [9.4466, 47.0446],
            },
          ],
        }),
        ('POST', '/api/v1/routing/reach') => () {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          asked.add(body);
          if (body['profile'] == 'alpine' && asked.length > 3) {
            return http.Response('{"detail":"no path near this point"}', 422);
          }
          return _json({
            'areas': [
              {'hours': 2, 'outline': _square(0.05)},
              {'hours': 4, 'outline': _square(0.1)},
              {'hours': 8, 'outline': _square(0.2)},
            ],
          });
        }(),
        _ => http.Response('', 404),
      };
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ReachScreen(
          api: Api('http://test', token: 't', client: client),
          map: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('place-search-open')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('place-search')), 'Sargans');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('place-result-0')));
    await tester.pumpAndSettle();

    expect(asked.single, {
      'from': {'lon': 9.4466, 'lat': 47.0446},
      'profile': 'hike',
      'back': true,
    });
    expect(find.text('Start: Sargans'), findsOneWidget);
    expect(find.text('bis 2 Stunden, hin und zurück'), findsOneWidget);
    expect(find.text('bis 8 Stunden, hin und zurück'), findsOneWidget);

    // One way.
    await tester.tap(find.byKey(const Key('reach-back')));
    await tester.pumpAndSettle();
    expect(asked.last.containsKey('back'), isFalse);
    expect(find.text('bis 2 Stunden'), findsOneWidget);
    expect(find.text('Bei deinem Tempo: 1.5-mal die Zeit der Wegweiser.'), findsOneWidget);

    await tester.tap(find.text('Alpinwandern (bis T6)'));
    await tester.pumpAndSettle();
    expect(asked.last['profile'], 'alpine');
    expect(find.byKey(const Key('reach-legend-4')), findsOneWidget);

    // Asked again, no path near the point: said, and no legend.
    await tester.tap(find.text('Wandern (bis T3)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpinwandern (bis T6)'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reach-error')), findsOneWidget);
    expect(find.byKey(const Key('reach-legend-4')), findsNothing);
  });
}
