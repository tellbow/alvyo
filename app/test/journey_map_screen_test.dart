import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/screens/journey_map_screen.dart';

Map<String, dynamic> _stage(String id, String title, String? route) => {
  'id': id,
  'title': title,
  'version': 1,
  'status': 'planned',
  'route': route == null
      ? null
      : {
          'id': route,
          'totals': {
            'distance_m': 12000.0,
            'ascent_m': 800.0,
            'descent_m': 300.0,
            'duration_s': 14400,
            'sac_grade': 2,
            'sac_max': 2,
          },
        },
};

JourneyDetail _journey({String id = 'j1', String firstRoute = 'r1'}) => JourneyDetail.fromJson({
  'id': id,
  'title': 'Via Alpina',
  'role': 'owner',
  'can_edit': true,
  'totals': {
    'distance_m': 24000.0,
    'ascent_m': 1600.0,
    'descent_m': 600.0,
    'duration_s': 28800,
    'sac_grade': 2,
    'sac_max': 2,
  },
  'progress': {'stages_done': 0, 'stages_total': 3},
  'profile': {
    'distance': [0, 1000, 2000, 3000, 4000],
    'points': [
      [9.5, 47.1, 1000],
      [9.51, 47.1, 1200],
      [9.52, 47.1, 900],
      [9.53, 47.1, 1100],
      [9.54, 47.1, 1000],
    ],
    'breaks': [0, 2],
  },
  'stage_list': [
    _stage('s1', 'Gaflei – Sargans', firstRoute),
    _stage('s2', '', null),
    _stage('s3', 'Sargans – Weisstannen', 'r3'),
  ],
});

void main() {
  final journey = _journey();

  test('each routed stage keeps its own part of the line, by its number', () {
    final lines = journey.stageLines;
    expect([for (final (i, l) in lines) (i, l.length)], [(0, 2), (2, 3)]);
    expect(lines[1].$2.first, [9.52, 47.1, 900]);
  });

  testWidgets('the map of all stages lists them in their colours', (tester) async {
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
        home: JourneyMapScreen(
          api: Api('http://test'),
          journey: journey,
          map: const SizedBox.expand(key: Key('map')),
        ),
      ),
    );
    expect(find.byKey(const Key('map')), findsOneWidget);
    expect(find.byKey(const Key('map-layers')), findsOneWidget);
    expect(find.text('Gaflei – Sargans'), findsOneWidget);
    expect(find.text('Etappe 2'), findsOneWidget);
    expect(find.text('Noch keine Route'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stage opens with the share token the journey was opened with', (tester) async {
    final support = Directory.systemTemp.createTempSync('support');
    addTearDown(() => support.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => support.path,
    );
    final asked = <Uri>[];
    final api = Api(
      'http://test',
      client: MockClient((req) async {
        asked.add(req.url);
        return http.Response('{"title": "Not Found", "status": 404}', 404);
      }),
    );
    const id = '0199a000-0000-7000-8000-00000000000b', route = '0199a000-0000-7000-8000-00000000000a';
    api.shareTokens[id] = 'c.collection.link';
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
        home: JourneyMapScreen(
          api: api,
          journey: _journey(id: id, firstRoute: route),
          map: const SizedBox.expand(),
        ),
      ),
    );
    await tester.tap(find.text('Gaflei – Sargans'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final call = asked.firstWhere((u) => u.path.startsWith('/api/v1/routes/$route'), orElse: () => fail('$asked'));
    expect(call.queryParameters['t'], 'c.collection.link');
  });
}
