import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:odysgeh/api.dart';
import 'package:odysgeh/l10n/app_localizations.dart';
import 'package:odysgeh/offline/packs.dart';
import 'package:odysgeh/screens/journeys_list.dart';

const _totals = {
  'distance_m': 18502.0,
  'ascent_m': 101.0,
  'descent_m': 1056.0,
  'duration_s': 17025,
  'sac_grade': 2,
  'sac_max': 3,
};

Map<String, dynamic> _stage(String id, String title, String? route, [Map<String, dynamic> extra = const {}]) => {
  'id': id,
  'title': title,
  'planned_date': null,
  'status': 'planned',
  'transfer_before': null,
  'start_place': null,
  'end_place': null,
  'accommodation': '',
  'accommodation_booked': false,
  'route': route == null ? null : {'id': route, 'totals': _totals},
  'gap': null,
  ...extra,
};

/// The server of a journey of three stages, two with a route; each route's
/// offline map is ready at once. Unreachable while [offline].
class FakeServer {
  var offline = false;
  final downloads = <String>[];

  http.Response _json(Object body) =>
      http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

  late final client = MockClient((req) async {
    if (offline) throw const SocketException('no connection');
    final p = req.url.path.replaceFirst('/api/v1', '');
    if (p == '/journeys') {
      return _json({
        'journeys': [
          {
            'id': 'j1',
            'title': 'Via Alpina',
            'stages': 3,
            'stages_done': 0,
            'distance_m': 32634.0,
            'ascent_m': 1118.0,
            'duration_s': 34463,
          },
        ],
      });
    }
    if (p == '/journeys/j1') {
      return _json({
        'id': 'j1',
        'title': 'Via Alpina',
        'totals': {..._totals, 'distance_m': 32634.0, 'ascent_m': 1118.0, 'duration_s': 34463},
        'progress': {'stages_done': 0, 'stages_total': 3},
        'stage_list': [
          _stage('s1', 'Gaflei – Sargans', 'r1', {
            'start_place': {'name': 'Gaflei, Klinik'},
            'end_place': {'name': 'Sargans'},
          }),
          _stage('s2', 'Sargans – Weisstannen', 'r2', {
            'planned_date': '2026-10-02',
            'transfer_before': 'pt',
            'gap': {'metres': 2100.0, 'status': 'transfer'},
            'accommodation': 'Gasthaus Alpenhof',
            'accommodation_booked': true,
          }),
          _stage('s3', '', null, {
            'gap': {'metres': 800.0, 'status': 'warning'},
          }),
        ],
      });
    }
    final m = RegExp(r'^/routes/(r\d)(/.*)?$').firstMatch(p);
    if (m == null) return http.Response('', 404);
    final (id, rest) = (m[1]!, m[2] ?? '');
    final key = 'route-$id-aaaaaa';
    switch ((req.method, rest)) {
      case ('GET', ''):
        return _json({
          'id': id,
          'title': id,
          'owner_username': 'anna',
          'totals': _totals,
          'legs': [
            {
              'coordinates': [
                [9.5, 47.1, 1000],
                [9.51, 47.1, 1010],
              ],
            },
          ],
        });
      case ('GET', '/turns'):
        return _json({'turns': <Object>[]});
      case ('POST', '/pack'):
        return _json({
          'state': 'ready',
          'key': key,
          'done': 1,
          'total': 1,
          'files': [
            {'layer': 'landeskarte', 'name': '$key-landeskarte.pmtiles', 'bytes': 4},
          ],
        });
      case ('GET', '/pack/landeskarte'):
        downloads.add(id);
        return http.Response.bytes(utf8.encode('PMTi'), 200);
    }
    return http.Response('', 404);
  });
}

void main() {
  // Offline maps and saved journeys go to a temporary directory; the
  // downloads singleton keeps the first one, so one for all tests.
  late Directory support;
  setUpAll(() {
    support = Directory.systemTemp.createTempSync('support');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => support.path,
    );
  });
  tearDownAll(() => support.deleteSync(recursive: true));

  /// Lets real file and network work go on until [f] shows (at most a few
  /// seconds).
  Future<void> until(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 200 && f.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpList(WidgetTester tester, Api api, Finder shows) async {
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(), // a new navigator: as when the app starts again
        locale: const Locale('de'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: JourneysList(api: api)),
      ),
    );
    await until(tester, shows);
  }

  testWidgets('a journey\'s stages, all saved offline, then opened without a connection', (tester) async {
    final server = FakeServer();
    final api = Api('https://odysgeh.test', token: 't', client: server.client);
    await pumpList(tester, api, find.text('Via Alpina'));
    expect(find.text('0 von 3 Etappen · 32.6 km · 9 h 35 min'), findsOneWidget);

    await tester.tap(find.text('Via Alpina'));
    await until(tester, find.text('Gaflei – Sargans'));
    expect(find.text('Gaflei – Sargans'), findsOneWidget);
    expect(find.text('18.5 km · 4 h 45 min · ↑ 101 m · T2–T3\nGaflei, Klinik → Sargans'), findsOneWidget);
    expect(
      find.text(
        '02.10.2026 · 18.5 km · 4 h 45 min · ↑ 101 m · T2–T3\n'
        'Überbrückt mit öffentlichem Verkehr\nUnterkunft: Gasthaus Alpenhof · gebucht',
      ),
      findsOneWidget,
    );
    // Without a title and route: numbered, and not to be opened.
    expect(find.text('Etappe 3'), findsOneWidget);
    expect(find.text('Noch keine Route\n800 m Abstand zum Ende der vorherigen Etappe'), findsOneWidget);
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Etappe 3')).enabled, isFalse);

    await tester.tap(find.byKey(const Key('journey-save')));
    await until(tester, find.byKey(const Key('journey-saved')));
    expect(find.byKey(const Key('journey-saved')), findsOneWidget);
    expect(server.downloads, ['r1', 'r2']);
    final store = PackStore(Directory('${support.path}/packs'));
    expect((await tester.runAsync(() => store.savedJourney('j1')))!.stages, hasLength(3));
    expect(find.byIcon(Icons.offline_pin), findsNWidgets(3)); // the header and both stages

    // Without a connection: the saved journey and its stages.
    server.offline = true;
    await pumpList(tester, api, find.byKey(const Key('journeys-offline')));
    expect(find.byKey(const Key('journeys-offline')), findsOneWidget);
    expect(find.text('0 von 3 Etappen · 32.6 km · 9 h 35 min'), findsOneWidget);
    await tester.tap(find.text('Via Alpina'));
    await until(tester, find.text('Sargans – Weisstannen'));
    expect(find.text('Sargans – Weisstannen'), findsOneWidget);
    expect(find.byKey(const Key('journey-saved')), findsOneWidget);
  });

  testWidgets('without a connection and nothing saved: says so', (tester) async {
    final server = FakeServer()..offline = true;
    final dir = Directory('${support.path}/packs');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    await pumpList(
      tester,
      Api('https://odysgeh.test', token: 't', client: server.client),
      find.text('Der Server ist nicht erreichbar.'),
    );
    expect(find.text('Der Server ist nicht erreichbar.'), findsOneWidget);
  });
}
