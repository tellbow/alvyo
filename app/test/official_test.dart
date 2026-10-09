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
import 'package:alvyo/screens/details.dart';
import 'package:alvyo/screens/route_screen.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _route({Object? official, bool canEdit = false}) => {
  'id': 'r1',
  'title': 'Au fil de la Versoix',
  'owner_username': 'wanderland',
  'role': canEdit ? 'owner' : 'viewer',
  'can_edit': canEdit,
  'profile': 'hike',
  'official': ?official,
  'totals': {
    'distance_m': 9700.0,
    'ascent_m': 137.0,
    'descent_m': 210.0,
    'duration_s': 8700,
    'sac_grade': 1,
    'sac_max': 2,
  },
  'anchors': [
    {'lon': 6.12, 'lat': 46.31},
    {'lon': 6.16, 'lat': 46.30},
  ],
  'legs': [
    {
      'coordinates': [
        [6.12, 46.31, 454.0],
        [6.16, 46.30, 395.0],
      ],
    },
  ],
};

// Share tokens ride along on calls for ids like these.
const _r = '01a12087-da5b-7055-9bbf-3e55c5e41960', _j = '01a12087-d863-7a05-8e00-217d4b618501';

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

  test('an official route is read, and linked on SchweizMobil in the app language', () {
    expect(Official.of({'number': '1', 'kind': 'national'})?.kind, 'national');
    expect(Official.of(null), isNull);
    expect(schweizMobilUrl('1', 'de').toString(), 'https://schweizmobil.ch/de/wanderland/route-1');
    expect(schweizMobilUrl('104', 'fr').toString(), 'https://schweizmobil.ch/fr/suisse-a-pied/itineraire-104');
    expect(schweizMobilUrl('7', 'it').toString(), 'https://schweizmobil.ch/it/svizzera-a-piedi/percorso-7');
    expect(schweizMobilUrl('7', 'en').toString(), 'https://schweizmobil.ch/en/hiking-in-switzerland/route-7');
  });

  test('copies are asked for with the item and its share token', () async {
    final asked = <String>[];
    final client = MockClient((req) async {
      asked.add('${req.method} ${req.url.path}?${req.url.query}');
      return req.url.path.startsWith('/api/v1/routes')
          ? _json({..._route(canEdit: true), 'id': 'r2'}, 201)
          : _json({
              'id': 'j2',
              'title': 'Via Alpina',
              'stage_list': <Object>[],
              'totals': {
                'distance_m': 0.0,
                'ascent_m': 0.0,
                'descent_m': 0.0,
                'duration_s': 0,
                'sac_grade': 0,
                'sac_max': 0,
              },
              'progress': {'stages_done': 0, 'stages_total': 0},
            }, 201);
    });
    final api = Api('http://test', token: 't', client: client)..shareTokenFor(_r, 'link');
    expect((await api.copyRoute(_r)).id, 'r2');
    expect((await api.copyJourney(_j)).id, 'j2');
    expect(asked, ['POST /api/v1/routes/$_r/copy?t=link', 'POST /api/v1/journeys/$_j/copy?']);
  });

  for (final official in [true, false]) {
    testWidgets(official ? 'an official route names its source' : "someone's route names its owner", (tester) async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/v1/routes/r1') {
          return _json(_route(official: official ? {'number': '104', 'kind': 'local'} : null));
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
            title: 'Au fil de la Versoix',
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
      if (official) {
        expect(find.byKey(const Key('official')), findsOneWidget);
        expect(find.text('Lokale Route 104 · auf SchweizMobil ↗', findRichText: true), findsOneWidget);
        expect(find.text('Offizielle Route von Wanderland Schweiz – Daten: ASTRA und SchweizMobil'), findsOneWidget);
        expect(find.byKey(const Key('owner')), findsNothing);
      } else {
        expect(find.byKey(const Key('official')), findsNothing);
        expect(find.byKey(const Key('owner')), findsOneWidget);
      }
      // Both can be taken as one's own.
      await tester.tap(find.byKey(const Key('item-menu')));
      await settle();
      expect(find.byKey(const Key('item-copy')), findsOneWidget);
      expect(find.text('Als eigene Route bearbeiten'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
