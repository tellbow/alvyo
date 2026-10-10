import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/screens/planner_screen.dart';
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
  test('the fewest hours whose area holds a point', () {
    final areas = [
      ReachArea.fromJson({'hours': 2, 'outline': _square(0.05)}),
      ReachArea.fromJson({
        'hours': 8,
        // With a hole around the 2-hour area's corner.
        'outline': [
          ..._square(0.2),
          [
            [9.44, 47.04],
            [9.46, 47.04],
            [9.46, 47.06],
            [9.44, 47.04],
          ],
        ],
      }),
    ];
    expect(reachedWithin(areas, (lon: 9.41, lat: 46.99)), 2);
    expect(reachedWithin(areas, (lon: 9.55, lat: 46.9)), 8);
    expect(reachedWithin(areas, (lon: 9.455, lat: 47.045)), isNull);
    expect(reachedWithin(areas, (lon: 9.7, lat: 47.0)), isNull);
  });

  // A start found by name: the areas of 2, 4 and 8 hours one way; there
  // and back; then alpine ways; a point without a path says so.
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
    });
    expect(find.text('Start: Sargans'), findsOneWidget);
    expect(find.text('bis 2 Stunden'), findsOneWidget);
    expect(find.text('Tippe in eine Fläche, um eine Route dorthin zu planen.'), findsOneWidget);

    // Back to the start.
    await tester.tap(find.byKey(const Key('reach-back')));
    await tester.pumpAndSettle();
    expect(asked.last['back'], isTrue);
    expect(find.text('bis 2 Stunden, hin und zurück'), findsOneWidget);
    expect(find.text('bis 8 Stunden, hin und zurück'), findsOneWidget);
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

  // A tap inside the areas offers a route there: the planner opens from the
  // start with the same profile, back to it with «Zurück zum Start»; a tap
  // outside starts anew.
  testWidgets('planning from the areas', (tester) async {
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final reach = <Map<String, dynamic>>[];
    final legs = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      return switch ((req.method, req.url.path)) {
        ('GET', '/api/v1/me') => _json({'id': 'u1', 'username': 'anna', 'display_name': 'Anna', 'speed_factor': 1.0}),
        ('GET', '/api/v1/places/search') => _json({
          'places': [
            {
              'name': 'Sargans',
              'kind': 'pt_stop',
              'detail': 'Bahnhof',
              'at': [9.4, 47.0],
            },
          ],
        }),
        ('POST', '/api/v1/routing/reach') => () {
          reach.add(jsonDecode(req.body) as Map<String, dynamic>);
          return _json({
            'areas': [
              {'hours': 2, 'outline': _square(0.05)},
              {'hours': 4, 'outline': _square(0.1)},
              {'hours': 8, 'outline': _square(0.2)},
            ],
          });
        }(),
        ('POST', '/api/v1/routing/leg') => () {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          legs.add(body);
          final from = body['from'] as Map, to = body['to'] as Map;
          return _json({
            'coordinates': [
              [from['lon'], from['lat'], 500],
              [to['lon'], to['lat'], 600],
            ],
            'distance_m': 1000.0,
            'ascent_m': 100.0,
            'descent_m': 20.0,
            'duration_s': 1800,
            'duration_reverse_s': 1500,
            'sac': {'grade': 4, 'max': 4, 'breakdown': <String, Object>{}, 'unofficial_m': 0.0},
            'details': {'sac': [], 'surface': [], 'way_type': [], 'trail': []},
            'warnings': <String>[],
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
    await tester.tap(find.text('Alpinwandern (bis T6)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reach-back')));
    await tester.pumpAndSettle();
    expect(reach, hasLength(3));
    final screen = tester.state<ReachScreenState>(find.byType(ReachScreen));

    // Inside the 4-hour area, not the 2-hour one.
    screen.tapped((lon: 9.47, lat: 47.0));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(BottomSheet), matching: find.text('bis 4 Stunden, hin und zurück')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('reach-plan-here')));
    await tester.pumpAndSettle();
    expect(find.byType(PlannerScreen), findsOneWidget);
    expect(
      [for (final l in legs) ((l['from'] as Map)['lon'], (l['to'] as Map)['lon'], l['profile'])],
      [(9.4, 9.47, 'alpine'), (9.47, 9.4, 'alpine')],
    );
    expect(find.text('Sargans'), findsOneWidget);
    expect(find.byKey(const Key('planner-return')), findsOneWidget);

    // Back: the areas are still there. «Von hier aus neu» starts from the
    // point, and so does a tap outside the areas, without asking.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reach-legend-8')), findsOneWidget);
    screen.tapped((lon: 9.47, lat: 47.0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reach-start-here')));
    await tester.pumpAndSettle();
    expect((reach.last['from'] as Map)['lon'], 9.47);
    expect(find.text('Start: Punkt auf der Karte'), findsOneWidget);
    screen.tapped((lon: 9.9, lat: 47.0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reach-plan-here')), findsNothing);
    expect((reach.last['from'] as Map)['lon'], 9.9);
  });
}
