import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/screens/travel_screen.dart';
import 'package:alvyo/travel.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, Object?> _place(String name, String kind, List<double> at, {String ref = ''}) => {
  'id': 'p-$name',
  'kind': kind,
  'name': name,
  'detail': '',
  'at': at,
  'distance_m': 0,
  'ref': ref,
};

/// Spiez → Zermatt in two stages: a stop at the start, a hut's point at the end.
JourneyDetail _journey() => JourneyDetail.fromJson({
  'id': 'j1',
  'title': 'Spiez – Zermatt',
  'stage_list': [
    for (final (i, s) in [
      (_place('Spiez', 'pt_stop', [7.68, 46.69], ref: '8507483'), '2026-07-04', [7.68, 46.69], [7.7, 46.6]),
      (_place('Hütte', 'hut', [7.7, 46.6]), '2026-07-06', [7.7, 46.6], [7.74831, 46.02449]),
    ].indexed)
      {
        'id': 's$i',
        'version': 1,
        'title': '',
        'planned_date': s.$2,
        'status': 'planned',
        'start_place': s.$1,
        'end_place': null,
        'route': {
          'id': 'r$i',
          'line': [s.$3, s.$4],
          'start': s.$3,
          'end': s.$4,
        },
      },
  ],
  'totals': {'distance_m': 1.0, 'ascent_m': 0.0, 'descent_m': 0.0, 'duration_s': 60, 'sac_grade': 1, 'sac_max': 1},
  'progress': {'stages_done': 0, 'stages_total': 2},
});

void main() {
  test('the journey is met at the first stage\'s stop and left from the end of the last line', () {
    final (:start, :end) = journeyEnds(_journey());
    expect(start?.at, '8507483');
    expect(start?.day, DateTime(2026, 7, 4));
    expect(end?.at, '7.74831,46.02449');
    expect(end?.day, DateTime(2026, 7, 6));
  });

  test('connections from home with a name, to a stop by its number, with the ways', () async {
    Uri? asked;
    final api = Api(
      'https://alvyo.test',
      token: 't',
      client: MockClient((req) async {
        asked = req.url;
        return _json({
          'trips': [
            {
              'start': '2026-07-04T04:02:00Z',
              'end': '2026-07-04T04:40:00Z',
              'transfers': 0,
              'legs': [
                {
                  'kind': 'walk',
                  'from': 'Zuhause',
                  'to': 'Thun',
                  'duration_min': 6,
                  'track': [
                    [7.6197, 46.764],
                    [7.63, 46.755],
                  ],
                },
              ],
            },
          ],
        });
      }),
    );
    final home = Home.fromJson({
      'id': 'h1',
      'name': 'Zuhause',
      'address': 'Länggasse 13B',
      'lon': 7.6197,
      'lat': 46.764,
    });
    final trips = await travelTrips(
      api,
      waySpot(const TravelWay(homeId: 'h1', time: '06:00'), [home])!,
      journeyEnds(_journey()).start!,
      const TravelWay(homeId: 'h1', time: '06:00'),
      to: true,
    );
    expect(asked?.queryParameters, {
      'from': '7.61970,46.76400',
      'to': '8507483',
      'from_name': 'Zuhause',
      'date': '2026-07-04',
      'time': '06:00',
      'arrive': 'false',
      'lines': 'true',
    });
    expect(trips.single.legs.single.track, hasLength(2));
    expect(
      const Travel(
        to: TravelWay(homeId: 'h1', time: '06:00'),
      ).toJson(),
      {
        'to': {'home_id': 'h1', 'time': '06:00', 'arrive': false},
      },
    );
  });

  testWidgets('the way home: a home chosen, then arriving instead of leaving, saved and searched again', (
    tester,
  ) async {
    Map<String, Object?> travel = {};
    final asked = <Map<String, String>>[];
    final client = MockClient((req) async {
      switch ((req.method, req.url.path)) {
        case ('GET', '/api/v1/me/homes'):
          return _json({
            'homes': [
              {'id': 'h1', 'name': 'Zuhause', 'address': 'Länggasse 13B, 3600 Thun', 'lon': 7.6197, 'lat': 46.764},
            ],
          });
        case ('PUT', '/api/v1/journeys/j1/travel'):
          travel = jsonDecode(req.body) as Map<String, Object?>;
          return _json(travel);
        case ('GET', '/api/v1/connections'):
          asked.add(req.url.queryParameters);
          return _json({
            'trips': [
              {
                'start': '2026-07-06T15:05:00Z',
                'end': '2026-07-06T16:50:00Z',
                'transfers': 2,
                'legs': [
                  {
                    'kind': 'ride',
                    'from': 'Zermatt',
                    'to': 'Visp',
                    'line': 'R 40',
                    'departure': '2026-07-06T15:05:00Z',
                    'arrival': '2026-07-06T16:10:00Z',
                  },
                ],
              },
              {
                'start': '2026-07-06T16:05:00Z',
                'end': '2026-07-06T17:50:00Z',
                'transfers': 2,
                'legs': [
                  {
                    'kind': 'ride',
                    'from': 'Zermatt',
                    'to': 'Visp',
                    'line': 'R 41',
                    'departure': '2026-07-06T16:05:00Z',
                    'arrival': '2026-07-06T17:10:00Z',
                  },
                ],
              },
            ],
          });
      }
      return http.Response('', 404);
    });
    final api = Api('https://alvyo.test', token: 't', client: client);
    Travel? result;
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
            onPressed: () async => result = await Navigator.of(context).push<Travel>(
              MaterialPageRoute(
                builder: (_) => TravelScreen(
                  api: api,
                  at: journeyEnds(_journey(), start: 'Start der Tour', end: 'Ende der Tour').end,
                  save: (t) => api.setTravel('j1', t),
                  travel: const Travel(),
                  to: false,
                  map: const SizedBox.expand(),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('open'));
    await settle();
    await tester.tap(find.byKey(const Key('travel-home')));
    await settle();
    await tester.tap(find.text('Zuhause').last);
    await settle();
    expect(travel, {
      'back': {'home_id': 'h1', 'time': '17:00', 'arrive': false},
    });
    expect(find.text('am 06.07.2026'), findsOneWidget);
    // Leaving after a time: the earliest first.
    expect(
      tester.getTopLeft(find.textContaining('R 40')).dy,
      lessThan(tester.getTopLeft(find.textContaining('R 41')).dy),
    );

    await tester.tap(find.text('An'));
    await settle();
    // Arriving by a time: the latest that fits first, and drawn.
    expect(
      tester.getTopLeft(find.textContaining('R 41')).dy,
      lessThan(tester.getTopLeft(find.textContaining('R 40')).dy),
    );
    expect((travel['back'] as Map)['arrive'], isTrue);
    expect(asked.last, containsPair('arrive', 'true'));
    // From the end of the line (no stop) to home.
    expect(asked.last['from'], '7.74831,46.02449');
    expect(asked.last['from_name'], 'Ende der Tour');
    expect(asked.last['to'], '7.61970,46.76400');
    expect(asked.last['to_name'], 'Zuhause');

    await Navigator.of(tester.element(find.byType(TravelScreen))).maybePop();
    await settle();
    expect(result?.back?.arrive, isTrue);
  });

  test("a route is met at its first and last point, named after the planner's points", () {
    final r = RouteDetail.fromJson({
      'id': 'r1',
      'title': 'Weisstannental',
      'owner_username': 'anna',
      'profile': 'hike',
      'visibility': 'private',
      'anchors': [
        {'lon': 9.34, 'lat': 46.99, 'name': 'Weisstannen, Oberdorf'},
        {'lon': 9.3, 'lat': 46.97},
      ],
      'legs': [
        {
          'coordinates': [
            [9.34, 46.99, 1000.0],
            [9.3, 46.97, 1200.0],
          ],
        },
      ],
      'totals': {'distance_m': 1.0, 'ascent_m': 0.0, 'descent_m': 0.0, 'duration_s': 60, 'sac_grade': 1, 'sac_max': 1},
    });
    final (:start, :end) = routeEnds(r, start: 'Start', end: 'Ziel');
    expect((start?.at, start?.name, start?.day), ('9.34000,46.99000', 'Weisstannen, Oberdorf', null));
    expect((end?.at, end?.name), ('9.30000,46.97000', 'Ziel'));
  });

  testWidgets('to a route from anywhere: a place found, saved for the route, on the day chosen', (tester) async {
    Map<String, Object?> travel = {};
    final asked = <Map<String, String>>[];
    final client = MockClient((req) async {
      switch ((req.method, req.url.path)) {
        case ('GET', '/api/v1/me/homes'):
          return _json({'homes': <Object>[]});
        case ('GET', '/api/v1/places/search'):
          return _json({
            'places': [
              {
                'name': 'Sargans',
                'kind': 'pt_stop',
                'detail': 'Zug',
                'at': [9.4447, 47.0448],
              },
            ],
          });
        case ('PUT', '/api/v1/routes/r1/travel'):
          travel = jsonDecode(req.body) as Map<String, Object?>;
          return _json(travel);
        case ('GET', '/api/v1/connections'):
          asked.add(req.url.queryParameters);
          return _json({'trips': <Object>[]});
      }
      return http.Response('', 404);
    });
    final api = Api('https://alvyo.test', token: 't', client: client);
    const at = (
      at: '9.34000,46.99000',
      name: 'Start',
      day: null,
      line: [
        [9.34, 46.99],
      ],
    );
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
        home: TravelScreen(
          api: api,
          at: at,
          travel: const Travel(),
          to: true,
          save: (t) => api.setRouteTravel('r1', t),
          pickDay: true,
          map: const SizedBox.expand(),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    await settle();
    // No home: the hint, and still another place to choose.
    expect(find.textContaining('fügst du in deinem Konto hinzu'), findsOneWidget);
    await tester.tap(find.byKey(const Key('travel-home')));
    await settle();
    await tester.tap(find.text('Anderer Ort …').last);
    await settle();
    await tester.tap(find.byKey(const Key('place-search-open')));
    await settle();
    await tester.enterText(find.byKey(const Key('place-search')), 'Sargans');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await settle();
    await tester.tap(find.byKey(const Key('place-result-0')));
    await settle();
    expect(travel, {
      'to': {
        'place': {'name': 'Sargans', 'lon': 9.4447, 'lat': 47.0448},
        'time': '07:00',
        'arrive': false,
      },
    });
    expect(asked.last['from'], '9.44470,47.04480');
    expect(asked.last['from_name'], 'Sargans');
    expect(asked.last['date'], DateTime.now().toIso8601String().substring(0, 10));
    expect(find.byKey(const Key('travel-day')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('travel-none')),
      100,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first,
    );
    expect(find.byKey(const Key('travel-none')), findsOneWidget);
  });
}
