import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/planner.dart';
import 'package:alvyo/screens/planner_screen.dart';
import 'package:alvyo/screens/route_screen.dart';

/// A leg from the request's from to to, with ele 500 → 600.
Map<String, dynamic> _leg(Map<String, dynamic> req, {int sac = 2, int sacMax = 2, int durationS = 1800}) {
  final from = req['from'] as Map<String, dynamic>, to = req['to'] as Map<String, dynamic>;
  return {
    'coordinates': [
      [from['lon'], from['lat'], 500],
      [to['lon'], to['lat'], 600],
    ],
    'distance_m': 1000.0,
    'ascent_m': 100.0,
    'descent_m': 20.0,
    'duration_s': durationS,
    'duration_reverse_s': 1500,
    'sac': {'grade': sac, 'max': sacMax, 'breakdown': <String, Object>{}, 'unofficial_m': 0.0},
    'details': {'sac': [], 'surface': [], 'way_type': [], 'trail': []},
    'warnings': <String>[],
  };
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

/// «lon>lon» of a leg request, enough to tell the test's points apart.
String _asked(http.Request req) {
  final j = jsonDecode(req.body) as Map<String, dynamic>;
  return '${(j['from'] as Map)['lon']}>${(j['to'] as Map)['lon']}';
}

void main() {
  group('RoutePlanner', () {
    test('only the legs a change affects are computed again', () async {
      final asked = <String>[];
      final planner = RoutePlanner(
        Api(
          'https://alvyo.test',
          client: MockClient((req) async {
            asked.add(_asked(req));
            return _json(_leg(jsonDecode(req.body) as Map<String, dynamic>));
          }),
        ),
      );
      planner.add(8.0, 46.0, name: 'A');
      planner.add(8.2, 46.0, name: 'C');
      await planner.idle();
      expect(asked, ['8.0>8.2']);

      planner.add(8.1, 46.0, name: 'B'); // A, C, B
      await planner.idle();
      expect(asked, ['8.0>8.2', '8.2>8.1']);

      planner.reorder(2, 1); // A, B, C: both legs are new
      await planner.idle();
      expect(asked.skip(2), ['8.0>8.1', '8.1>8.2']);

      planner.remove(planner.points[1].id); // A, C again: known
      await planner.idle();
      expect(asked, hasLength(4));
      expect(planner.complete, isTrue);

      planner.reorder(1, 0); // C, A
      await planner.idle();
      expect(asked.last, '8.2>8.0');

      planner.setProfile('alpine'); // every leg again
      await planner.idle();
      expect(asked, hasLength(6));
      expect(planner.legs.single.leg, isNotNull);
    });

    test('an answer that comes after the points changed is dropped', () async {
      final answers = <String, Completer<http.Response>>{};
      final planner = RoutePlanner(
        Api('https://alvyo.test', client: MockClient((req) => (answers[_asked(req)] = Completer()).future)),
      );
      planner.add(8.0, 46.0);
      planner.add(8.1, 46.0);
      expect(planner.legs.single.loading, isTrue);

      planner.remove(planner.points[1].id);
      planner.add(8.3, 46.0);
      await pumpEventQueue(); // the requests reach the server
      final body = {
        'from': {'lon': 8.0, 'lat': 46.0},
        'to': {'lon': 8.1, 'lat': 46.0},
      };
      answers['8.0>8.1']!.complete(_json(_leg(body)));
      await pumpEventQueue();
      expect(planner.legs.single.loading, isTrue, reason: 'the old leg is not shown');
      expect(planner.line, isEmpty);

      answers['8.0>8.3']!.complete(
        _json(
          _leg({
            'from': {'lon': 8.0, 'lat': 46.0},
            'to': {'lon': 8.3, 'lat': 46.0},
          }),
        ),
      );
      await planner.idle();
      expect(planner.line.last[0], 8.3);
      planner.dispose();
    });

    test('a leg without a path is an error on that leg; others are asked again', () async {
      var status = 422;
      var calls = 0;
      final planner = RoutePlanner(
        Api(
          'https://alvyo.test',
          client: MockClient((req) async {
            calls++;
            if (_asked(req) == '8.1>8.2' && status != 200) return _json({'detail': 'no path'}, status);
            return _json(_leg(jsonDecode(req.body) as Map<String, dynamic>));
          }),
        ),
      );
      planner.add(8.0, 46.0);
      planner.add(8.1, 46.0);
      planner.add(8.2, 46.0);
      await planner.idle();
      expect([for (final l in planner.legs) l.error], [null, 422]);
      expect(planner.complete, isFalse);

      planner.retry(); // no path stays no path
      await planner.idle();
      expect(calls, 2);

      planner.remove(planner.points[2].id);
      planner.add(8.2, 46.0);
      await planner.idle();
      expect(calls, 2);

      status = 503;
      planner.setProfile('alpine');
      await planner.idle();
      expect(planner.legs[1].error, 503);
      status = 200;
      planner.retry();
      await planner.idle();
      expect(planner.legs[1].leg, isNotNull, reason: 'a passing failure is asked again');
      expect(planner.complete, isTrue);
    });

    test('totals: sums, the hardest grade, one line without repeated joints', () async {
      final planner = RoutePlanner(
        Api(
          'https://alvyo.test',
          client: MockClient((req) async {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            return _json(switch (_asked(req)) {
              '8.0>8.1' => _leg(body, sac: 2, sacMax: 4),
              '8.1>8.2' => _leg(body, sac: 3, sacMax: 3, durationS: 3600),
              _ => _leg(body, sac: 3, sacMax: 5),
            });
          }),
        ),
      );
      for (final lon in [8.0, 8.1, 8.2, 8.3]) {
        planner.add(lon, 46.0);
      }
      await planner.idle();
      final t = planner.totals;
      expect(t.distanceM, 3000);
      expect(t.ascentM, 300);
      expect(t.descentM, 60);
      expect(t.durationS, 1800 + 3600 + 1800);
      expect((t.sacGrade, t.sacMax), (3, 5));
      expect([for (final c in planner.line) c[0]], [8.0, 8.1, 8.2, 8.3]);
    });

    test('the title from the first and last point names', () {
      final planner = RoutePlanner(Api('https://alvyo.test', client: MockClient((_) async => http.Response('', 500))));
      expect(planner.suggestedTitle, '');
      planner.add(8.0, 46.0, name: 'Sargans');
      expect(planner.suggestedTitle, 'Sargans');
      planner.add(8.1, 46.0);
      expect(planner.suggestedTitle, 'Sargans');
      planner.add(8.2, 46.0, name: 'Weisstannen');
      expect(planner.suggestedTitle, 'Sargans – Weisstannen');
    });
  });

  group('PlannerScreen', () {
    late Directory support;
    setUpAll(() {
      support = Directory.systemTemp.createTempSync('support');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => support.path,
      );
    });
    tearDownAll(() => support.deleteSync(recursive: true));
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    testWidgets('points by search, a failed leg, totals at the hiker\'s pace, then saved and opened', (tester) async {
      Map<String, dynamic>? saved;
      final client = MockClient((req) async {
        switch (req.url.path) {
          case '/api/v1/me':
            return _json({'id': 'u1', 'username': 'wodan', 'display_name': 'Wodan', 'speed_factor': 1.5});
          case '/api/v1/places/search':
            final q = req.url.queryParameters['q']!;
            final lon = {'Sargans': 9.44, 'Weisstannen': 9.35, 'Gletscher': 9.2}[q]!;
            return _json({
              'places': [
                {
                  'name': q,
                  'kind': 'pt_stop',
                  'detail': '',
                  'at': [lon, 47.0],
                },
              ],
            });
          case '/api/v1/routing/leg':
            if (_asked(req) == '9.35>9.2') return _json({'detail': 'no path'}, 422);
            return _json(_leg(jsonDecode(req.body) as Map<String, dynamic>));
          case '/api/v1/routes' when req.method == 'POST':
            saved = jsonDecode(req.body) as Map<String, dynamic>;
            return _json({
              'id': 'r1',
              'title': saved!['title'],
              'owner_username': 'wodan',
              'totals': {
                'distance_m': 1000.0,
                'ascent_m': 100.0,
                'descent_m': 20.0,
                'duration_s': 1800,
                'sac_grade': 2,
                'sac_max': 2,
              },
              'legs': saved!['legs'],
            }, 201);
          default:
            return http.Response('', 404); // the route screen then shows an error
        }
      });
      // A tall phone: the panel shows everything.
      tester.view.physicalSize = const Size(400, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
          home: PlannerScreen(
            api: Api('https://alvyo.test', token: 't', client: client),
            map: const ColoredBox(color: Colors.grey),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Suche Start und Ziel oder tippe auf die Karte.'), findsOneWidget);

      Future<void> search(String q) async {
        await tester.enterText(find.byKey(const Key('place-search')), q);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        await tester.tap(find.byKey(const Key('place-result-0')));
        await tester.pump();
        await tester.pump();
      }

      await search('Sargans');
      expect(find.widgetWithText(TextField, 'Ziel suchen …'), findsOneWidget);
      await search('Weisstannen');
      expect(find.byKey(const Key('planner-totals')), findsOneWidget);
      // 30 min at pace 1.5: 45 min.
      expect(find.text('1.0 km · 45 min · ↑ 100 m ↓ 20 m · T2'), findsOneWidget);

      await search('Gletscher');
      expect(find.byKey(const Key('planner-leg-error-1')), findsOneWidget);
      expect(find.text('Kein Weg in der Nähe. Entferne den Punkt oder setze einen anderen.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('planner-save'))).onPressed, isNull);

      await tester.ensureVisible(find.byKey(const Key('planner-remove-2')));
      await tester.tap(find.byKey(const Key('planner-remove-2')));
      await tester.pump();
      expect(find.byKey(const Key('planner-leg-error-1')), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('planner-save')));
      await tester.tap(find.byKey(const Key('planner-save')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Sargans – Weisstannen'), findsOneWidget);
      await tester.tap(find.byKey(const Key('planner-save-confirm')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(saved!['title'], 'Sargans – Weisstannen');
      expect(saved!['profile'], 'hike');
      expect(saved!['anchors'], [
        {'lon': 9.44, 'lat': 47.0, 'name': 'Sargans'},
        {'lon': 9.35, 'lat': 47.0, 'name': 'Weisstannen'},
      ]);
      expect(saved!['legs'], hasLength(1));
      expect(find.byType(RouteScreen), findsOneWidget);
      expect(find.byType(PlannerScreen), findsNothing);
    });
  });
}
