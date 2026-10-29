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
import 'package:alvyo/offline/packs.dart';
import 'package:alvyo/screens/journeys_list.dart';

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

  /// The user may change the journey.
  var canEdit = false;

  /// owner, editor or viewer; the owner may delete it.
  var role = 'viewer';
  var deleted = false;

  /// Stage 1 as the server has it; patches need its version.
  var s1Status = 'planned';
  var s1Version = 1;
  final patches = <Map<String, dynamic>>[];

  http.Response _json(Object body) =>
      http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

  late final client = MockClient((req) async {
    if (offline) throw const SocketException('no connection');
    final p = req.url.path.replaceFirst('/api/v1', '');
    if (p == '/journeys/j1' && req.method == 'DELETE') {
      deleted = true;
      return http.Response('', 204);
    }
    if (p == '/journeys') {
      return _json({
        'journeys': [
          if (!deleted)
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
    if (p == '/journeys/j1/areas') {
      return _json({
        'areas': [
          {
            'kind': 'wildlife_rest',
            'id': '1',
            'name': 'Weisstannen Siez',
            'binding': true,
            'rule': {'de': 'Zutrittsverbot', 'fr': "Interdiction d'accès", 'it': 'Divieto di accesso'},
            'period': {'from': '12-01', 'to': '04-20'},
            'stages': [2],
          },
        ],
      });
    }
    if (p == '/journeys/j1/stages/s1' && req.method == 'PATCH') {
      if (req.headers['if-match'] != '"$s1Version"') {
        return http.Response(jsonEncode({'detail': 'the stage was changed in the meantime'}), 412);
      }
      final b = jsonDecode(req.body) as Map<String, dynamic>;
      patches.add(b);
      s1Status = b['status'] as String;
      s1Version++;
    }
    if (p == '/journeys/j1' || p == '/journeys/j1/stages/s1') {
      return _json({
        'id': 'j1',
        'title': 'Via Alpina',
        'role': role,
        'can_edit': canEdit,
        'totals': {..._totals, 'distance_m': 32634.0, 'ascent_m': 1118.0, 'duration_s': 34463},
        'progress': {'stages_done': s1Status == 'done' ? 1 : 0, 'stages_total': 3},
        'profile': {
          'distance': [0, 1000, 2000, 3000],
          'points': [
            [9.5, 47.1, 1000],
            [9.51, 47.1, 1200],
            [9.52, 47.1, 900],
            [9.53, 47.1, 1100],
          ],
          'breaks': [0, 2],
        },
        'stage_list': [
          _stage('s1', 'Gaflei – Sargans', 'r1', {
            'start_place': {'name': 'Gaflei, Klinik'},
            'end_place': {'name': 'Sargans'},
            'status': s1Status,
            'version': s1Version,
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
    final api = Api('https://alvyo.test', token: 't', client: server.client);
    await pumpList(tester, api, find.text('Via Alpina'));
    // The tour card: the kind above, the figures, the stages as a bar.
    expect(find.text('32.6\u00a0km · 9\u00a0h 35\u00a0min · ↑\u00a01118\u00a0m'), findsOneWidget);
    expect(find.text('0 / 3'), findsOneWidget);

    await tester.tap(find.text('Via Alpina'));
    await until(tester, find.text('Gaflei – Sargans'));
    expect(find.text('Gaflei – Sargans'), findsOneWidget);
    expect(
      find.text(
        '18.5\u00a0km · 4\u00a0h 45\u00a0min · ↑\u00a0101\u00a0m · T2–T3\nGaflei, Klinik → Sargans',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        '02.10.2026 · 18.5\u00a0km · 4\u00a0h 45\u00a0min · ↑\u00a0101\u00a0m · T2–T3\n'
        'Überbrückt mit öffentlichem Verkehr\n\uFFFC Gasthaus Alpenhof · gebucht', // the bed, then the name
        findRichText: true,
      ),
      findsOneWidget,
    );
    // The profile and the areas are on «Übersicht».
    expect(find.byKey(const Key('elevation-profile')), findsNothing);
    await tester.tap(find.byKey(const Key('tab-overview')));
    await tester.pump();
    expect(find.byKey(const Key('elevation-profile')), findsOneWidget, reason: 'all stages\' profile');
    final line = find.byKey(const Key('protected-areas'));
    await until(tester, line); // asked for after the journey
    await tester.ensureVisible(find.descendant(of: line, matching: find.byType(OutlinedButton)));
    await tester.tap(find.descendant(of: line, matching: find.byType(OutlinedButton)));
    await tester.pumpAndSettle();
    final area = find.text('Weisstannen Siez (Wildruhezone, verbindlich)\nZutrittsverbot · 1.12. bis 20.4. · Etappe 2');
    expect(area, findsOneWidget);
    await tester.tapAt(const Offset(200, 20)); // beside the sheet
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('tab-stages')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tab-stages')));
    await tester.pump();
    // Without a title and route: numbered, and opens its sheet (details,
    // public transport) instead of a map.
    expect(find.text('Etappe 3'), findsOneWidget);
    expect(find.text('Noch keine Route\n800\u00a0m Abstand zum Ende der vorherigen Etappe'), findsOneWidget);
    await tester.tap(find.text('Etappe 3'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // closes it
    await tester.pumpAndSettle();

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
    // The tour card: the kind above, the figures, the stages as a bar.
    expect(find.text('32.6\u00a0km · 9\u00a0h 35\u00a0min · ↑\u00a01118\u00a0m'), findsOneWidget);
    expect(find.text('0 / 3'), findsOneWidget);
    await tester.tap(find.text('Via Alpina'));
    await until(tester, find.text('Sargans – Weisstannen'));
    expect(find.text('Sargans – Weisstannen'), findsOneWidget);
    expect(find.byKey(const Key('journey-saved')), findsOneWidget);
  });

  testWidgets('the owner deletes a journey, with what is saved of it', (tester) async {
    final server = FakeServer()..role = 'owner';
    final api = Api('https://alvyo.test', token: 't', client: server.client);
    await pumpList(tester, api, find.text('Via Alpina'));
    await tester.tap(find.text('Via Alpina'));
    await until(tester, find.text('Gaflei – Sargans'));
    // Saved already by the test before, else now.
    if (find.byKey(const Key('journey-save')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('journey-save')));
    }
    await until(tester, find.byKey(const Key('journey-saved')));
    final store = PackStore(Directory('${support.path}/packs'));
    expect(await tester.runAsync(() => store.saved('r1')), isNotNull);

    await tester.tap(find.byKey(const Key('item-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-delete')));
    await tester.pumpAndSettle();
    expect(
      find.text('Etappentour mit allen Etappen und Routen löschen? Das lässt sich nicht rückgängig machen.'),
      findsOneWidget,
    );
    // Cancelled: nothing happens.
    await tester.tap(find.byKey(const Key('delete-cancel')));
    await tester.pumpAndSettle();
    expect(server.deleted, isFalse);

    await tester.tap(find.byKey(const Key('item-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await until(tester, find.text('Noch keine Etappentouren. Plane sie auf der Website.'));
    await tester.pumpAndSettle(); // the journey's page slides away
    expect(server.deleted, isTrue);
    expect(find.text('Via Alpina'), findsNothing, reason: 'back in the list, without it');
    expect(await tester.runAsync(() => store.savedJourney('j1')), isNull);
    expect(await tester.runAsync(() => store.saved('r1')), isNull);
  });

  testWidgets('only the owner can delete a journey', (tester) async {
    final server = FakeServer()
      ..canEdit = true
      ..role = 'editor';
    final api = Api('https://alvyo.test', token: 't', client: server.client);
    await pumpList(tester, api, find.text('Via Alpina'));
    await tester.tap(find.text('Via Alpina'));
    await until(tester, find.text('Gaflei – Sargans'));
    await tester.tap(find.byKey(const Key('item-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-edit')), findsOneWidget);
    expect(find.byKey(const Key('item-delete')), findsNothing);
    // An editor adds stages; the journey's map is a tap away.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    final panel = find.ancestor(of: find.byKey(const Key('stage-0')), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(const Key('journey-add-stage')), 200, scrollable: panel);
    expect(find.byKey(const Key('journey-add-stage')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('journey-map')), -200, scrollable: panel);
    expect(find.byKey(const Key('journey-map')), findsOneWidget);
  });

  testWidgets('a viewer adds no stages', (tester) async {
    final server = FakeServer()
      ..canEdit = false
      ..role = 'viewer';
    final api = Api('https://alvyo.test', token: 't', client: server.client);
    await pumpList(tester, api, find.text('Via Alpina'));
    await tester.tap(find.text('Via Alpina'));
    await until(tester, find.text('Gaflei – Sargans'));
    await tester.scrollUntilVisible(
      find.byKey(const Key('stage-2')),
      200,
      scrollable: find.ancestor(of: find.byKey(const Key('stage-0')), matching: find.byType(Scrollable)).first,
    );
    expect(find.byKey(const Key('journey-add-stage')), findsNothing);
  });

  testWidgets('without a connection and nothing saved: says so', (tester) async {
    final server = FakeServer()..offline = true;
    final dir = Directory('${support.path}/packs');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    await pumpList(
      tester,
      Api('https://alvyo.test', token: 't', client: server.client),
      find.text('Der Server ist nicht erreichbar.'),
    );
    expect(find.text('Der Server ist nicht erreichbar.'), findsOneWidget);
  });

  testWidgets('a stage is ticked off as hiked; a change by someone else meanwhile is shown', (tester) async {
    final server = FakeServer()..canEdit = true;
    final api = Api('https://alvyo.test', token: 't', client: server.client);
    await pumpList(tester, api, find.text('Via Alpina'));
    await tester.tap(find.text('Via Alpina'));
    await until(tester, find.byKey(const Key('stage-done-0')));
    // Only stages with a route can be hiked.
    expect(find.byKey(const Key('stage-done-2')), findsNothing);

    await tester.tap(find.byKey(const Key('stage-done-0')));
    await until(tester, find.text('1 von 3 Etappen · 32.6\u00a0km · 9\u00a0h 35\u00a0min · ↑\u00a01118\u00a0m'));
    expect(server.patches.single['status'], 'done');
    expect(server.patches.single['done_on'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(tester.widget<IconButton>(find.byKey(const Key('stage-done-0'))).isSelected, isTrue);

    // Someone else set it back meanwhile: refused, and the new state shows.
    server
      ..s1Status = 'planned'
      ..s1Version = 7;
    await tester.tap(find.byKey(const Key('stage-done-0')));
    await until(tester, find.text('Jemand hat die Etappe inzwischen geändert. Hier ist der neue Stand.'));
    await until(tester, find.text('0 von 3 Etappen · 32.6\u00a0km · 9\u00a0h 35\u00a0min · ↑\u00a01118\u00a0m'));
    expect(server.patches, hasLength(1));
    expect(tester.widget<IconButton>(find.byKey(const Key('stage-done-0'))).isSelected, isFalse);
  });

  testWidgets('viewers cannot tick stages off', (tester) async {
    final server = FakeServer();
    await pumpList(tester, Api('https://alvyo.test', token: 't', client: server.client), find.text('Via Alpina'));
    await tester.tap(find.text('Via Alpina'));
    await until(tester, find.text('Gaflei – Sargans'));
    expect(find.byKey(const Key('stage-done-0')), findsNothing);
  });

  testWidgets('pulling the journey down loads it again', (tester) async {
    final server = FakeServer();
    await pumpList(tester, Api('https://alvyo.test', token: 't', client: server.client), find.text('Via Alpina'));
    await tester.tap(find.text('Via Alpina'));
    await until(tester, find.text('Gaflei – Sargans'));
    server.s1Status = 'done'; // changed elsewhere
    await tester.fling(find.text('Gaflei – Sargans'), const Offset(0, 400), 1000);
    await until(tester, find.text('1 von 3 Etappen'));
    expect(find.text('1 von 3 Etappen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
