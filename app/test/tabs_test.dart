import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/navigation/gps.dart';
import 'package:alvyo/screens/discover_tab.dart';
import 'package:alvyo/screens/feed_tab.dart';
import 'package:alvyo/screens/plan_tab.dart';
import 'package:alvyo/screens/tours_tab.dart';

const _totals = {
  'distance_m': 11100.0,
  'ascent_m': 742.0,
  'descent_m': 742.0,
  'duration_s': 14100,
  'sac_grade': 2,
  'sac_max': 3,
};

Map<String, dynamic> _route(String id, String title, {String? done, String owner = 'wodan'}) => {
  'id': id,
  'title': title,
  'owner_username': owner,
  'visibility': 'private',
  'totals': _totals,
  'tags': <String>[],
  'done_on': ?done,
};

Map<String, dynamic> _journey(String id, String title, {String? done, String owner = 'wodan'}) => {
  'id': id,
  'title': title,
  'owner_username': owner,
  'visibility': 'private',
  'stages': 6,
  'stages_done': 2,
  'distance_m': 121300.0,
  'ascent_m': 5556.0,
  'duration_s': 138300,
  'tags': <String>[],
  'done_on': ?done,
};

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('de'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

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

  Future<void> until(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 100 && f.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Touren: routes, journeys and shared ones in one list, by state and kind', (tester) async {
    final api = Api(
      'https://alvyo.test',
      token: 't',
      client: MockClient(
        (req) async => switch (req.url.path) {
          '/api/v1/routes' => _json({
            'routes': [_route('r1', 'Ober Altgfähl – Napf'), _route('r2', 'Säntis', done: '2026-08-01')],
          }),
          '/api/v1/journeys' => _json({
            'journeys': [_journey('j1', 'Thun – Zermatt')],
          }),
          '/api/v1/shared' => _json({
            'routes': [_route('r3', 'JaNey', owner: 'bossm8')],
            'journeys': <Object>[],
            'collections': <Object>[],
          }),
          _ => http.Response('', 404),
        },
      ),
    );
    await tester.pumpWidget(_app(ToursTab(api: api)));
    await until(tester, find.text('Thun – Zermatt'));

    // Geplant: own and shared, not the hiked one; the kind above each title.
    for (final title in ['Ober Altgfähl – Napf', 'Thun – Zermatt', 'JaNey']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Säntis'), findsNothing);
    expect(find.text('ETAPPENTOUR · 6 ETAPPEN'), findsOneWidget);
    expect(find.text('2 / 6'), findsOneWidget);
    expect(find.text('11.1 km · 3 h 55 min · ↑ 742 m · T2–T3'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('tours-kind-journeys')));
    await tester.pump();
    expect(find.text('Ober Altgfähl – Napf'), findsNothing);
    expect(find.text('Thun – Zermatt'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tours-kind-shared')));
    await tester.pump();
    expect(find.text('JaNey'), findsOneWidget);
    expect(find.text('Thun – Zermatt'), findsNothing);

    await tester.tap(find.byKey(const Key('tours-kind-all')));
    await tester.tap(find.text('Gewandert'));
    await tester.pump();
    expect(find.text('Säntis'), findsOneWidget);
    expect(find.text('Ober Altgfähl – Napf'), findsNothing);
  });

  testWidgets('Entdecken: what people one follows published, tours nearby, places found', (tester) async {
    tester.view.physicalSize = const Size(400, 1600); // all of it at once
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final asked = <String>[];
    final api = Api(
      'https://alvyo.test',
      token: 't',
      client: MockClient((req) async {
        asked.add(req.url.path);
        return switch (req.url.path) {
          '/api/v1/feed' => _json({
            'items': [
              for (var i = 0; i < 5; i++)
                {
                  'kind': 'route',
                  'id': 'f$i',
                  'title': 'Feed $i',
                  'owner_username': 'bossm8',
                  'owner_name': 'Boss',
                  'published_at': '2026-10-0${i + 1}T10:00:00Z',
                  ..._totals,
                },
            ],
          }),
          '/api/v1/discover' => _json({
            'items': [
              {
                'kind': 'route',
                'id': 'n1',
                'title': 'Nahe Runde',
                'owner_username': 'anna',
                ..._totals,
                'longest_s': 14100,
              },
            ],
            'more': false,
          }),
          '/api/v1/places/search' => _json({
            'places': [
              {
                'name': 'Napf',
                'kind': 'name',
                'detail': '1408 m',
                'at': [7.94, 47.0],
              },
            ],
          }),
          _ => http.Response('', 404),
        };
      }),
    );
    PlanMode? planned;
    await tester.pumpWidget(
      _app(DiscoverTab(api: api, onPlan: (m) => planned = m, position: () async => (lon: 8.0, lat: 47.0))),
    );
    await until(tester, find.text('Nahe Runde'));
    // Three of the feed («Alle» for the rest), the nearby tour.
    expect(find.text('Feed 0'), findsOneWidget);
    expect(find.text('Feed 2'), findsOneWidget);
    expect(find.text('Feed 3'), findsNothing);
    expect(find.text('Nahe Runde'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tool-reach')));
    expect(planned, PlanMode.reach);

    await tester.enterText(find.byKey(const Key('discover-search')), 'Napf');
    await tester.pump(const Duration(milliseconds: 400));
    await until(tester, find.text('1408 m'));
    expect(find.text('1408 m'), findsOneWidget);
    expect(find.text('Feed 0'), findsNothing);
  });

  testWidgets('Neuigkeiten: a friend\'s hikes, one on a route one may not see, and a comment', (tester) async {
    Uri? asked;
    final api = Api(
      'https://alvyo.test',
      token: 't',
      client: MockClient((req) async {
        asked = req.url;
        return _json({
          'items': [
            {
              'kind': 'comment',
              'target': 'route',
              'id': 'r1',
              'title': 'Rundweg',
              'owner_username': 'tom',
              'owner_name': 'Tom Huber',
              'published_at': '2026-10-28T10:00:00Z',
              ..._totals,
              'excerpt': 'Wie steil ist der Grat?',
            },
            {
              'kind': 'hike',
              'target': 'route',
              'id': 'r2',
              'title': 'Höhenweg',
              'owner_username': 'bea',
              'owner_name': 'Bea Keller',
              'published_at': '2026-10-28T09:00:00Z',
              'done_on': '2026-10-27',
              ..._totals,
            },
            {
              'kind': 'hike',
              'target': 'route',
              'id': '',
              'title': '',
              'owner_username': 'bea',
              'owner_name': 'Bea Keller',
              'published_at': '2026-10-27T09:00:00Z',
              'done_on': '2026-10-25',
              ..._totals,
            },
          ],
        });
      }),
    );
    await tester.pumpWidget(_app(Scaffold(body: FeedTab(api: api))));
    await until(tester, find.text('Höhenweg'));
    expect(asked?.queryParameters['activity'], 'true');
    expect(find.text('«Wie steil ist der Grat?»'), findsOneWidget);
    expect(find.textContaining('ist gewandert'), findsNWidgets(2));
    expect(find.textContaining('27.10.2026'), findsOneWidget); // the day hiked, not when marked
    expect(find.text('Eine eigene Route'), findsOneWidget);
  });

  group('Entdecken without a position', () {
    Future<void> pump(WidgetTester tester, LocationAccess access, Future<LonLat?> Function() position) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = Api(
        'https://alvyo.test',
        token: 't',
        client: MockClient(
          (req) async => switch (req.url.path) {
            '/api/v1/feed' => _json({'items': []}),
            _ => _json({'items': []}),
          },
        ),
      );
      await tester.pumpWidget(
        _app(DiscoverTab(api: api, onPlan: (_) {}, position: position, access: () async => access)),
      );
    }

    testWidgets('the location allowed but not found: no «Standort erlauben», a retry that finds it', (tester) async {
      var asked = 0;
      await pump(tester, LocationAccess.allowed, () async => ++asked == 1 ? null : (lon: 8.0, lat: 47.0));
      await until(tester, find.byKey(const Key('nearby-unknown')));
      expect(find.text('Standort erlauben'), findsNothing);
      await tester.tap(find.text('Nochmals versuchen'));
      await until(tester, find.byKey(const Key('nearby-empty')));
      expect(asked, 2);
    });

    testWidgets('not allowed yet: asks for it', (tester) async {
      await pump(tester, LocationAccess.ask, () async => null);
      await until(tester, find.byKey(const Key('nearby-no-position')));
      expect(find.text('Standort erlauben'), findsOneWidget);
    });

    testWidgets('switched off: says so', (tester) async {
      await pump(tester, LocationAccess.off, () async => null);
      await until(tester, find.byKey(const Key('nearby-no-position')));
      expect(find.text('Der Standort ist ausgeschaltet: schalte ihn in den Einstellungen ein.'), findsOneWidget);
      expect(find.text('Einstellungen öffnen'), findsOneWidget);
    });

    testWidgets('refused for good: the way to the settings', (tester) async {
      await pump(tester, LocationAccess.settings, () async => null);
      await until(tester, find.byKey(const Key('nearby-no-position')));
      expect(
        find.text('Dein Standort ist nicht bekannt. Erlaube Alvyo den Standort in den Einstellungen des Telefons.'),
        findsOneWidget,
      );
      expect(find.text('Einstellungen öffnen'), findsOneWidget);
    });
  });

  testWidgets('Planen: three modes and «Importieren»', (tester) async {
    await tester.pumpWidget(
      _app(PlanTab(api: Api('https://alvyo.test'), modes: (mode, saved) => Text('mode ${mode.name}'))),
    );
    expect(find.text('mode day'), findsOneWidget);
    await tester.tap(find.text('Mehrtägig'));
    await tester.pump();
    expect(find.text('mode multi'), findsOneWidget);
    await tester.tap(find.text('Reichweite'));
    await tester.pump();
    expect(find.text('mode reach'), findsOneWidget);

    await tester.tap(find.byKey(const Key('plan-import')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('import-watch')), findsOneWidget);
  });

  testWidgets('Planen › Importieren › Datei: what the server cannot use is said', (tester) async {
    var answer = http.Response('{"detail":"this is not a GPX, KML, TCX or FIT file"}', 422);
    final api = Api('https://alvyo.test', token: 't', client: MockClient((req) async => answer));
    var saved = 0;
    await tester.pumpWidget(
      _app(
        PlanTab(
          api: api,
          modes: (mode, saved) => const SizedBox(),
          onSaved: () => saved++,
          pickFile: () async => XFile.fromData(utf8.encode('<gpx/>'), name: 'tour.gpx'),
        ),
      ),
    );
    Future<void> importIt() async {
      await tester.tap(find.byKey(const Key('plan-import')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-file')));
      await tester.pumpAndSettle();
      await until(tester, find.byType(SnackBar));
    }

    await importIt();
    expect(find.textContaining('keine Spur'), findsOneWidget);
    expect(saved, 0);

    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).clearSnackBars();
    await tester.pumpAndSettle();
    answer = _json({
      'routes': <Object>[],
      'skipped': [
        {'name': 'Mont Blanc', 'reason': 'outside'},
      ],
    });
    await importIt();
    expect(find.textContaining('über die Grenze'), findsOneWidget);
  });
}
