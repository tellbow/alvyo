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
import 'package:alvyo/screens/journey_plan_screen.dart';
import 'package:alvyo/screens/journey_screen.dart';

const _totals = {
  'distance_m': 15000.0,
  'ascent_m': 900.0,
  'descent_m': 400.0,
  'duration_s': 16200, // 4 h 30 min Swiss hiking time
  'sac_grade': 2,
  'sac_max': 3,
};

Map<String, dynamic> _place(String id, {String kind = 'hut', String website = ''}) => {
  'id': id,
  'kind': kind,
  'name': id,
  'detail': '',
  'at': [7.7, 46.4],
  'distance_m': 50.0,
  'website': website,
};

Map<String, dynamic> _stage(
  String? end, {
  String? earlier,
  String? later,
  String kind = 'hut',
  String website = '',
  bool overMax = false,
  bool underMin = false,
}) => {
  'start_place': null,
  'end_place': end == null ? null : _place(end, kind: kind, website: website),
  'earlier': earlier == null ? null : _place(earlier),
  'later': later == null ? null : _place(later),
  'accommodation': end ?? '',
  'totals': _totals,
  'over_max': overMax,
  'under_min': underMin,
  'profile': 'hike',
  'anchors': [
    {'lon': 7.6, 'lat': 46.7},
    {'lon': 7.7, 'lat': 46.4},
  ],
  'legs': [
    {
      'coordinates': [
        [7.6, 46.7, 560],
        [7.7, 46.4, 1200],
      ],
    },
  ],
};

Map<String, dynamic> _proposal(List<Map<String, dynamic>> stages) => {
  'stages': stages,
  'target_s': 16200,
  'min_s': 0,
  'max_s': 20000,
};

/// The planning endpoints; [plan] and [suggest] give the answers, the
/// requests are kept.
class _Server {
  final requests = <(String, Map<String, dynamic>)>[];
  Future<http.Response> Function(Map<String, dynamic> body) plan = (_) async => _json(
    _proposal([
      _stage('Blüemlisalphütte', later: 'Kandersteg', website: 'https://bluemlisalp.ch', overMax: true),
      _stage('Gasthaus Gemmi', kind: 'hotel', earlier: 'Schwarenbach', underMin: true),
      _stage(null),
    ]),
  );
  Future<http.Response> Function(Map<String, dynamic> body) suggest = (_) async => _json({
    'suggestions': [
      {
        'points': [
          {'lon': 7.6, 'lat': 46.7},
          {'lon': 7.7, 'lat': 46.0},
        ],
        'via': '',
        'proposal': _proposal([_stage('Kandersteg'), _stage('Gfellalp'), _stage('Gampel'), _stage(null)]),
      },
      {
        'points': [
          {'lon': 7.6, 'lat': 46.7},
          {'lon': 7.62, 'lat': 46.4},
          {'lon': 7.7, 'lat': 46.0},
        ],
        'via': 'Gemmi',
        'proposal': _proposal([
          _stage('Kandersteg', later: 'Sunnbüel'),
          _stage('Gemmi'),
          _stage('Gampel'),
          _stage('St. Niklaus'),
          _stage(null),
        ]),
      },
    ],
  });

  static http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

  late final client = MockClient((req) async {
    final p = req.url.path.replaceFirst('/api/v1', '');
    final body = req.body.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map<String, dynamic>;
    if (req.method == 'POST') requests.add((p, body));
    switch ((req.method, p)) {
      case ('GET', '/me'):
        return _json({'id': 'u1', 'username': 'anna', 'display_name': 'Anna', 'speed_factor': 1.25});
      case ('GET', '/places/search'):
        final q = req.url.queryParameters['q']!;
        return _json({
          'places': [
            {
              'name': q.startsWith('Th') ? 'Thun' : (q.startsWith('Vi') ? 'Visp' : 'Zermatt'),
              'kind': 'pt_stop',
              'detail': 'Zug',
              'at': q.startsWith('Th') ? [7.63, 46.75] : (q.startsWith('Vi') ? [7.88, 46.29] : [7.75, 46.02]),
            },
          ],
        });
      case ('POST', '/journeys/plan'):
        return plan(body);
      case ('POST', '/journeys/suggest'):
        return suggest(body);
      case ('POST', '/journeys'):
        return _json(_journey(body['title'] as String));
      case ('GET', '/journeys/j9'):
        return _json(_journey('Thun – Zermatt'));
      case ('GET', '/journeys/j9/areas'):
        return _json({'areas': <Object>[]});
    }
    return http.Response('', 404);
  });

  static Map<String, dynamic> _journey(String title) => {
    'id': 'j9',
    'title': title,
    'can_edit': true,
    'totals': _totals,
    'progress': {'stages_done': 0, 'stages_total': 0},
    'stage_list': <Object>[],
  };
}

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

  Future<void> open(WidgetTester tester, _Server server) async {
    // Tall enough for the whole panel.
    tester.view.physicalSize = const Size(1000, 7000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = Api('https://alvyo.test', token: 't', client: server.client);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => TextButton(
            key: const Key('open'),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => JourneyPlanScreen(api: api, showMap: false))),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String q) async {
    await tester.tap(find.byKey(const Key('place-search-open')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('place-search')), q);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('place-result-0')));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String key) => tester.widget<ButtonStyleButton>(find.byKey(Key(key))).enabled;

  String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets('plans the days by hours at the hiker\'s pace, then ends a day later', (tester) async {
    final server = _Server();
    await open(tester, server);
    expect(enabled(tester, 'jplan-submit'), isFalse);

    await search(tester, 'Thun');
    await search(tester, 'Zermatt');
    expect(find.text('Thun'), findsOneWidget);
    expect(find.text('Zermatt'), findsOneWidget);

    // From 5 to 7 hours at a pace of 1.25: 4 to 5.6 Swiss hours.
    await tap(tester, 'jplan-by-hours');
    await tester.enterText(find.byKey(const Key('jplan-hours-min')), '5');
    await tester.enterText(find.byKey(const Key('jplan-hours-max')), '7');
    await tap(tester, 'jplan-kind-campsite');
    await tap(tester, 'jplan-submit');

    final (path, body) = server.requests.single;
    expect(path, '/journeys/plan');
    expect(body['points'], [
      {'lon': 7.63, 'lat': 46.75},
      {'lon': 7.75, 'lat': 46.02},
    ]);
    expect(body['min_hours'], 4.0);
    expect(body['max_hours'], closeTo(5.6, 1e-9));
    expect(body.containsKey('days'), isFalse);
    expect(body['kinds'], ['hut', 'hotel', 'campsite']);
    expect(body['profile'], 'hike');

    expect(text(tester, 'jplan-summary'), '3 Tage · 45.0\u00a0km');
    // 4 h 30 min Swiss time at 1.25.
    expect(find.textContaining('5\u00a0h 40\u00a0min'), findsNWidgets(3));
    expect(text(tester, 'jplan-end-0'), '→ Blüemlisalphütte');
    expect(text(tester, 'jplan-end-2'), '→ bis zum Ziel');
    expect(find.text('Website: https://bluemlisalp.ch'), findsOneWidget);
    expect(find.textContaining('weiss OpenStreetMap selten'), findsOneWidget, reason: 'the hut only');
    expect(find.textContaining('Länger als gewünscht'), findsOneWidget);
    expect(find.textContaining('Kürzer als gewünscht'), findsOneWidget);
    expect(find.byKey(const Key('jplan-way-0')), findsNothing);
    // Named after the places found.
    expect(tester.widget<TextField>(find.byKey(const Key('jplan-title'))).controller!.text, 'Thun – Zermatt');

    // The first night later: the others stay.
    await tap(tester, 'jplan-later-0');
    final (_, again) = server.requests.last;
    expect(again['ends'], ['Kandersteg', 'Gasthaus Gemmi']);
    expect(again['points'], body['points']);
  });

  testWidgets('by days with a most per day; no way', (tester) async {
    final server = _Server()..plan = (_) async => _Server._json({'message': 'no path'}, 422);
    await open(tester, server);
    await search(tester, 'Thun');
    await search(tester, 'Zermatt');
    await tester.enterText(find.byKey(const Key('jplan-days')), '4');
    await tester.enterText(find.byKey(const Key('jplan-max')), '7,5');
    await tester.pump();
    await tap(tester, 'jplan-submit');

    final (_, body) = server.requests.single;
    expect(body['days'], 4);
    expect(body['max_hours'], 6.0);
    expect(body.containsKey('min_hours'), isFalse);
    expect(text(tester, 'jplan-problem'), 'Zwischen diesen Punkten gibt es mit diesem Profil keinen Weg.');

    // Asking for no days at all is not sent.
    await tester.enterText(find.byKey(const Key('jplan-days')), '0');
    await tester.pump();
    expect(enabled(tester, 'jplan-submit'), isFalse);
    expect(enabled(tester, 'jplan-suggest'), isFalse);
  });

  // The iPhone's number pad has no key to close it, and it covers the
  // buttons below: a tap outside the field or scrolling the panel closes it.
  testWidgets('the number pad closes on a tap outside and on scrolling', (tester) async {
    await open(tester, _Server());
    await tester.tap(find.byKey(const Key('jplan-days')));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tapAt(tester.getTopLeft(find.byKey(const Key('jplan-panel'))) + const Offset(4, 4));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse, reason: 'tapped outside');

    await tester.tap(find.byKey(const Key('jplan-days')));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.drag(find.byKey(const Key('jplan-panel')), const Offset(0, -100));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse, reason: 'scrolled');
  });

  testWidgets('a stop before the destination and the order changed, as in the day\'s planner', (tester) async {
    await open(tester, _Server());
    await search(tester, 'Thun');
    await search(tester, 'Zermatt');
    List<String> names() => [
      for (var i = 0; i < 3; i++)
        if (find.byKey(Key('jplan-point-$i')).evaluate().isNotEmpty)
          (tester.widget<ListTile>(find.byKey(Key('jplan-point-$i'))).title as Text).data!,
    ];

    await tap(tester, 'jplan-via');
    final via = find.byKey(const Key('jplan-via-search'));
    // Only the stop's search while it is open (feedback issue 19).
    expect(find.byKey(const Key('place-search-open')), findsOneWidget);
    expect(find.text('Abbrechen'), findsOneWidget);
    await tester.tap(find.descendant(of: via, matching: find.byKey(const Key('place-search-open'))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('place-search')), 'Visp');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('place-result-0')));
    await tester.pumpAndSettle();
    expect(names(), ['Thun', 'Visp', 'Zermatt']);
    expect(via, findsNothing);
    expect(find.widgetWithText(TextField, 'Weiteres Ziel suchen …'), findsOneWidget);

    await tap(tester, 'jplan-down-0');
    expect(names(), ['Visp', 'Thun', 'Zermatt']);
    await tap(tester, 'jplan-up-2');
    expect(names(), ['Visp', 'Zermatt', 'Thun']);
    expect(enabled(tester, 'jplan-submit'), isTrue);
  });

  testWidgets('an answer for points changed meanwhile is dropped', (tester) async {
    final server = _Server();
    final answer = Completer<http.Response>();
    final first = server.plan;
    server.plan = (body) => answer.future;
    await open(tester, server);
    await search(tester, 'Thun');
    await search(tester, 'Zermatt');
    await tester.tap(find.byKey(const Key('jplan-submit')));
    await tester.pump();
    expect(find.byKey(const Key('jplan-busy')), findsOneWidget);
    expect(enabled(tester, 'jplan-suggest'), isFalse, reason: 'one plan at a time');

    await tester.tap(find.byKey(const Key('jplan-remove-1')));
    await tester.pump();
    answer.complete(await first({}));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('jplan-busy')), findsNothing);
    expect(find.byKey(const Key('jplan-summary')), findsNothing);
    expect(find.byKey(const Key('jplan-point-1')), findsNothing);
  });

  testWidgets('several ways: choose one, go on along another at a shared night, move a night', (tester) async {
    final server = _Server();
    await open(tester, server);
    await search(tester, 'Thun');
    await search(tester, 'Zermatt');
    await tap(tester, 'jplan-suggest');

    expect(server.requests.single.$1, '/journeys/suggest');
    expect(server.requests.single.$2['days'], 3);
    expect(find.text('Weg 1: direkt'), findsOneWidget);
    expect(find.text('Weg 2: über Gemmi'), findsOneWidget);
    expect(find.textContaining('4 Tage · 60.0\u00a0km\nKandersteg · Gfellalp · Gampel'), findsOneWidget);
    expect(find.textContaining('Wo zwei Wege am gleichen Ort übernachten'), findsOneWidget);
    expect(text(tester, 'jplan-summary'), '4 Tage · 60.0\u00a0km');

    // Way 1 sleeps in Kandersteg and Gampel as way 2 does.
    expect(find.byKey(const Key('jplan-switch-0-1')), findsOneWidget);
    expect(find.byKey(const Key('jplan-switch-1-1')), findsNothing);
    expect(find.byKey(const Key('jplan-switch-2-1')), findsOneWidget);
    expect(find.text('Ab hier weiter auf Weg 2'), findsNWidgets(2));

    // Over the first way to Gampel, then on along the second.
    await tap(tester, 'jplan-switch-2-1');
    expect(text(tester, 'jplan-summary'), '5 Tage · 75.0\u00a0km');
    expect(text(tester, 'jplan-end-2'), '→ Gampel · Weg 1');
    expect(text(tester, 'jplan-end-3'), '→ St. Niklaus · Weg 2');
    // Put together: the nights cannot be moved one by one.
    expect(find.byKey(const Key('jplan-later-0')), findsNothing);
    expect(find.byKey(const Key('jplan-switch-3-0')), findsNothing);
    expect(find.byKey(const Key('jplan-switch-0-1')), findsOneWidget);

    // The second way as a whole: its night can move, along its points.
    await tap(tester, 'jplan-way-1');
    expect(text(tester, 'jplan-end-1'), '→ Gemmi');
    await tap(tester, 'jplan-later-0');
    final (path, body) = server.requests.last;
    expect(path, '/journeys/plan');
    expect(body['points'], hasLength(3));
    expect(body['ends'], ['Sunnbüel', 'Gemmi', 'Gampel', 'St. Niklaus']);
    // The answer replaces the second way's days; it stays the one chosen.
    expect(text(tester, 'jplan-summary'), '3 Tage · 45.0\u00a0km');
    expect(
      tester
          .widget<ListTile>(find.descendant(of: find.byKey(const Key('jplan-way-1')), matching: find.byType(ListTile)))
          .selected,
      isTrue,
    );
  });

  testWidgets('creates the journey with the days and opens it', (tester) async {
    final server = _Server();
    await open(tester, server);
    await search(tester, 'Thun');
    await search(tester, 'Zermatt');
    await tap(tester, 'jplan-submit');
    await tester.tap(find.byKey(const Key('jplan-create')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final (path, body) = server.requests.last;
    expect(path, '/journeys');
    expect(body['title'], 'Thun – Zermatt');
    expect(body['visibility'], 'private');
    final stages = body['stages'] as List;
    expect(stages, hasLength(3));
    expect((stages.first as Map)['end_place_id'], 'Blüemlisalphütte');
    expect((stages.last as Map).containsKey('end_place_id'), isFalse);
    expect(find.byType(JourneyScreen), findsOneWidget);
    expect(find.byType(JourneyPlanScreen), findsNothing);
  });
}
