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
import 'package:alvyo/screens/route_screen.dart';
import 'package:alvyo/screens/travel_screen.dart';

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

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

  // Sargans – Weisstannen crosses several wildlife rest areas: on an iPhone
  // the list under the map scrolls, the map keeps its place, and the
  // keyboard of the dialog before (still closing) takes no room.
  testWidgets('many protected areas and the keyboard: the panel scrolls, nothing overflows', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(tester.view.reset);
    final client = MockClient((req) async {
      switch (req.url.path) {
        case '/api/v1/routes/r1':
          return _json({
            'id': 'r1',
            'title': 'Sargans – Weisstannen',
            'owner_username': 'wodan',
            'profile': 'hike',
            'totals': {
              'distance_m': 16600.0,
              'ascent_m': 1121.0,
              'descent_m': 600.0,
              'duration_s': 19780,
              'sac_grade': 2,
              'sac_max': 2,
            },
            'legs': [
              {
                'coordinates': [
                  for (var i = 0; i < 50; i++) [9.44 - i * 0.002, 47.04 - i * 0.001, 500.0 + i * 20],
                ],
              },
            ],
          });
        case '/api/v1/routes/r1/weather' when req.url.queryParameters['date'] != null:
          return _json({
            'run': '2026-09-28T18:00:00Z',
            'places': [
              {
                'roles': ['start', 'top', 'end'],
                'point': {'name': 'Sargans', 'height': 482.0, 'lon': 9.44, 'lat': 47.04},
                'days': <Object>[],
                'climate': {
                  'month': 12,
                  'station': 'Bad Ragaz',
                  'height': 496.0,
                  'rain_station': 'Sargans',
                  'min_c': -2.6,
                  'max_c': 4.4,
                  'rain_mm': 81.3,
                  'rain_days': 9.6,
                },
              },
            ],
          });
        case '/api/v1/routes/r1/weather':
          return _json({
            'run': '2026-09-28T18:00:00Z',
            'places': [
              {
                'roles': ['start'],
                'point': {'name': 'Sargans', 'height': 482.0, 'lon': 9.44, 'lat': 47.04},
                'days': [
                  {
                    'date': '2026-09-29',
                    'min_c': 4.4,
                    'max_c': 18.6,
                    'rain_mm': 0,
                    'rain_lo_mm': 0,
                    'rain_hi_mm': 0.2,
                    'symbol': 1,
                  },
                  {
                    'date': '2026-09-30',
                    'min_c': 4.4,
                    'max_c': 15,
                    'rain_mm': 3.2,
                    'rain_lo_mm': 0.4,
                    'rain_hi_mm': 9.8,
                  },
                ],
              },
              {
                'roles': ['top', 'end'],
                'point': {'name': 'Weisstannen', 'height': 1004.0, 'lon': 9.35, 'lat': 46.99},
                'days': [
                  {'date': '2026-09-29', 'min_c': 4.4, 'max_c': 14, 'rain_mm': 0, 'rain_lo_mm': 0, 'rain_hi_mm': 0},
                  {'date': '2026-09-30', 'min_c': 4.4, 'max_c': 11, 'rain_mm': 4, 'rain_lo_mm': 1, 'rain_hi_mm': 12},
                ],
              },
            ],
          });
        case '/api/v1/routes/r1/social':
          return _json({
            'likes': 0,
            'liked': false,
            'can_comment': true,
            'can_moderate': false,
            'comments_enabled': true,
            'comments': [
              {
                'id': 'c1',
                'author_username': 'anna',
                'author_name': 'Anna',
                'body': 'Schön!',
                'created_at': '2026-09-27T10:00:00Z',
                'can_edit': false,
                'can_delete': false,
              },
            ],
          });
        case '/api/v1/routes/r1/pois':
          return _json({
            'pois': [
              {
                'kind': 'water',
                'name': '',
                'at': [9.43, 47.03],
                'along_m': 1200.0,
                'off_m': 20.0,
              },
              {
                'kind': 'peak',
                'name': 'Gonzen',
                'ele': 1830,
                'at': [9.42, 47.03],
                'along_m': 5300.0,
                'off_m': 90.0,
              },
            ],
          });
        case '/api/v1/routes/r1/areas':
          return _json({
            'areas': [
              for (var i = 0; i < 8; i++)
                {
                  'kind': 'wildlife_rest',
                  'name': 'Wildruhezone Nummer $i',
                  'binding': true,
                  'rule': {'de': 'Zutrittsverbot'},
                  'period': {'from': '12-20', 'to': '04-30'},
                },
            ],
            'notices': [
              {
                'kind': 'closure',
                'id': '1',
                'title': {'de': 'Seewäldli', 'fr': 'Seewäldli', 'it': 'Seewäldli', 'en': 'Seewäldli'},
                'reason': {
                  'de': 'Forstarbeiten',
                  'fr': 'Travaux forestiers',
                  'it': 'Lavori forestali',
                  'en': 'Forestry work',
                },
                'from': '2026-08-31',
                'to': '2026-10-30',
              },
              {
                'kind': 'shooting',
                'id': '2',
                'title': {'de': 'Geissalp', 'fr': '', 'it': ''},
                'days': [
                  {'date': '2026-09-29', 'from': '0800', 'to': '1700'},
                  {'date': '2026-09-30'},
                ],
                'phone': '+41 58 467 19 90',
              },
            ],
          });
      }
      return http.Response('', 404);
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
        home: RouteScreen(
          api: Api('http://test', token: 't', client: client),
          id: 'r1',
          title: 'Sargans – Weisstannen',
          map: const SizedBox.expand(key: Key('map')),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Along the way in a tab of its own, with its count; one kind alone by its chip.
    expect(find.text('1.2\u00a0km · Trinkwasser'), findsNothing);
    await tester.tap(find.text('Unterwegs 2'));
    await tester.pump();
    expect(find.text('1.2\u00a0km · Trinkwasser'), findsOneWidget);
    expect(find.text('5.3\u00a0km · Gonzen · Gipfel · 1830\u00a0m'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('pois-peak')));
    await tester.pump(); // ensureVisible only scrolls
    await tester.tap(find.byKey(const Key('pois-peak')));
    await tester.pump();
    expect(find.text('1.2\u00a0km · Trinkwasser'), findsNothing);
    await tester.tap(find.byKey(const Key('tab-overview')));
    await tester.pump();
    // Comments in their own tab with the count, and the count above opens it (feedback issue 46).
    expect(find.text('Kommentare 1'), findsOneWidget);
    expect(find.text('Schön!'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('comments-count')));
    await tester.pump(); // ensureVisible only scrolls
    await tester.tap(find.byKey(const Key('comments-count')));
    await tester.pump();
    expect(find.text('Schön!'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tab-overview')));
    await tester.pump();
    // Closures and areas: a line with how many, the list in a sheet.
    expect(find.text('Sperrungen und Schiessen'), findsOneWidget);
    expect(find.textContaining('Wildruhezone Nummer 0'), findsNothing);
    expect(find.text('8 anzeigen'), findsOneWidget);
    await tester.ensureVisible(find.textContaining('2 anzeigen'));
    await tester.pump(); // ensureVisible only scrolls
    await tester.tap(find.textContaining('2 anzeigen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Seewäldli (Wanderweg gesperrt)\nForstarbeiten · 31.8.–30.10.'), findsOneWidget);
    expect(
      find.textContaining('Geissalp (Schiessen der Armee)\n29.9. 08:00–17:00, 30.9. · +41 58 467 19 90'),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(200, 20)); // beside the sheet
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('8 anzeigen'));
    await tester.tap(find.text('8 anzeigen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Wildruhezone Nummer 0'), findsOneWidget);
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    // The weather of today, then of the day chosen.
    expect(find.text('Start · Sargans, 482\u00a0m\n4–19\u00a0°C · trocken'), findsOneWidget);
    expect(find.text('Höchster Punkt, Ziel · Weisstannen, 1004\u00a0m\n4–14\u00a0°C · trocken'), findsOneWidget);
    await tester.ensureVisible(find.text('Morgen'));
    await tester.tap(find.text('Morgen'));
    await tester.pump();
    expect(find.text('Start · Sargans, 482\u00a0m\n4–15\u00a0°C · 3.2 mm Niederschlag (0.4–9.8 mm)'), findsOneWidget);
    // Today's symbol as an icon, named.
    expect(find.bySemanticsLabel('sonnig'), findsNothing, reason: 'the 30th has no symbol');
    await tester.tap(find.text('Heute'));
    await tester.pump();
    expect(find.bySemanticsLabel('sonnig'), findsOneWidget);
    // A day beyond the forecast: what is usual in its month.
    await tester.ensureVisible(find.byKey(const Key('weather-date')));
    await tester.tap(find.byKey(const Key('weather-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '24.12.2026');
    await tester.tap(find.text('OK'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Start, Höchster Punkt, Ziel · Sargans, 482\u00a0m\nÜblich im Dezember: -3–4\u00a0°C, an 10 von 31 Tagen Regen, 81 mm im Monat',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('weather-climate-source')), findsOneWidget);
    // The map keeps at least half of what is left above the keyboard.
    expect(tester.getSize(find.byKey(const Key('map'))).height, greaterThan(150));
    expect(tester.takeException(), isNull);
    // The buttons are at the top of the panel, above the tabs.
    await tester.scrollUntilVisible(
      find.byKey(const Key('nav-start')),
      -100,
      scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first,
    );
    expect(find.byKey(const Key('nav-start')), findsOneWidget);
  });

  // Someone else's recorded hike of 600 m: the server leaves out its start
  // and end, which is all of it.
  testWidgets("someone else's short hike: no line, a note, nothing to start", (tester) async {
    final client = MockClient((req) async {
      if (req.url.path == '/api/v1/routes/r1') {
        return _json({
          'id': 'r1',
          'title': 'Wanderung, 28.09.2026',
          'owner_username': 'anna',
          'profile': 'hike',
          'can_edit': false,
          'role': 'viewer',
          'hike': {'at': '2026-09-28T08:00:00Z', 'duration_s': 600},
          'totals': {
            'distance_m': 600.0,
            'ascent_m': 0.0,
            'descent_m': 0.0,
            'duration_s': 480,
            'sac_grade': 1,
            'sac_max': 1,
          },
          'anchors': [],
          'legs': [],
        });
      }
      return http.Response('', 404);
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
        home: RouteScreen(
          api: Api('http://test', token: 't', client: client),
          id: 'r1',
          title: 'Wanderung',
          map: const SizedBox.expand(),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.text('Diese Wanderung ist zu kurz, um sie anderen zu zeigen: Start und Ende sind verborgen.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('nav-start')), findsNothing);
    expect(find.byKey(const Key('offline-save')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // A stage has no way there and back of its own: its journey's is from home.
  for (final journey in [null, 'j1']) {
    testWidgets('the way there and back ${journey == null ? 'on a route' : 'not on a stage'}', (tester) async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/v1/routes/r1') {
          return _json({
            'id': 'r1',
            'title': 'Weisstannen',
            'owner_username': 'wodan',
            'role': 'owner',
            'can_edit': true,
            'journey_id': journey,
            'profile': 'hike',
            'totals': {
              'distance_m': 1000.0,
              'ascent_m': 10.0,
              'descent_m': 10.0,
              'duration_s': 900,
              'sac_grade': 1,
              'sac_max': 1,
            },
            'legs': [
              {
                'coordinates': [
                  [9.44, 47.04, 500.0],
                  [9.45, 47.04, 510.0],
                ],
              },
            ],
          });
        }
        return http.Response('', 404);
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
          home: RouteScreen(
            api: Api('http://test', token: 't', client: client),
            id: 'r1',
            title: 'Weisstannen',
            map: const SizedBox.expand(),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(TravelTiles, skipOffstage: false), journey == null ? findsOneWidget : findsNothing);
    });
  }

  // A route of one's own is deleted from its menu, after asking; a stage's
  // route is deleted with its stage.
  for (final (role, journey, menu) in [('owner', null, true), ('editor', null, false), ('owner', 'j1', false)]) {
    testWidgets('delete as $role${journey == null ? '' : ' of a stage'}', (tester) async {
      var deleted = false;
      final client = MockClient((req) async {
        switch ((req.method, req.url.path)) {
          case ('DELETE', '/api/v1/routes/r1'):
            deleted = true;
            return http.Response('', 204);
          case ('GET', '/api/v1/routes/r1'):
            return _json({
              'id': 'r1',
              'title': 'Rundweg',
              'owner_username': 'wodan',
              'role': role,
              'journey_id': journey,
              'profile': 'hike',
              'totals': {
                'distance_m': 1000.0,
                'ascent_m': 10.0,
                'descent_m': 10.0,
                'duration_s': 900,
                'sac_grade': 1,
                'sac_max': 1,
              },
              'legs': [
                {
                  'coordinates': [
                    [9.44, 47.04, 500.0],
                    [9.45, 47.04, 510.0],
                  ],
                },
              ],
            });
        }
        return _json({'areas': <Object>[]});
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
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RouteScreen(
                    api: Api('http://test', token: 't', client: client),
                    id: 'r1',
                    title: 'Rundweg',
                    map: const SizedBox.expand(),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      // The screen's spinner never settles: pumped a while instead.
      Future<void> settle() async {
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.tap(find.text('open'));
      await settle();
      // The menu has more (GPX, editing …); «Löschen» only for the owner.
      await tester.tap(find.byKey(const Key('item-menu')));
      await settle();
      expect(find.byKey(const Key('item-delete')), menu ? findsOneWidget : findsNothing);
      if (!menu) return;
      await tester.tap(find.byKey(const Key('item-delete')));
      await settle();
      expect(find.text('Route löschen? Das lässt sich nicht rückgängig machen.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('delete-confirm')));
      await settle();
      expect(deleted, isTrue);
      expect(find.byType(RouteScreen), findsNothing, reason: 'left after deleting');
    });
  }

  // «Als gewandert markieren» asks the day and says so; one's own mark can
  // be taken back.
  testWidgets('mark a route as hiked from its menu', (tester) async {
    final sent = <String>[];
    final client = MockClient((req) async {
      switch ((req.method, req.url.path)) {
        case ('PUT', '/api/v1/routes/r1/done'):
          sent.add('PUT ${req.body}');
          return _json({'done_on': '2026-10-01', 'done_marked': true});
        case ('DELETE', '/api/v1/routes/r1/done'):
          sent.add('DELETE');
          return _json({'done_marked': false});
        case ('GET', '/api/v1/routes/r1'):
          return _json({
            'id': 'r1',
            'title': 'Rundweg',
            'owner_username': 'wodan',
            'role': 'owner',
            'profile': 'hike',
            'totals': {
              'distance_m': 1000.0,
              'ascent_m': 10.0,
              'descent_m': 10.0,
              'duration_s': 900,
              'sac_grade': 1,
              'sac_max': 1,
            },
            'legs': [
              {
                'coordinates': [
                  [9.44, 47.04, 500.0],
                  [9.45, 47.04, 510.0],
                ],
              },
            ],
          });
      }
      return _json({'areas': <Object>[]});
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
        home: RouteScreen(
          api: Api('http://test', token: 't', client: client),
          id: 'r1',
          title: 'Rundweg',
          map: const SizedBox.expand(),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    expect(find.byKey(const Key('done-on')), findsNothing);
    await tester.tap(find.byKey(const Key('item-menu')));
    await settle();
    expect(find.byKey(const Key('item-undone')), findsNothing, reason: 'no mark to take back');
    await tester.tap(find.byKey(const Key('item-done')));
    await settle();
    await tester.tap(find.text('OK')); // today
    await settle();
    expect(sent.single, startsWith('PUT {"done_on":"'));
    expect(find.text('✓ Gewandert am 01.10.2026'), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-menu')));
    await settle();
    await tester.tap(find.byKey(const Key('item-undone')));
    await settle();
    expect(sent.last, 'DELETE');
    expect(find.byKey(const Key('done-on')), findsNothing);
  });
}
