import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';

const _totals = {
  'distance_m': 12000.0,
  'ascent_m': 800.0,
  'descent_m': 300.0,
  'duration_s': 16200,
  'duration_reverse_s': 14000,
  'ele_min_m': 500.0,
  'ele_max_m': 1500.0,
  'sac_grade': 2,
  'sac_max': 2,
};

Map<String, dynamic> _leg(List<List<double>> coordinates) => {
  'coordinates': coordinates,
  'distance_m': 1200.0,
  'ascent_m': 80.0,
  'descent_m': 10.0,
  'ele_min_m': 500.0,
  'ele_max_m': 580.0,
  'duration_s': 1500,
  'duration_reverse_s': 1300,
  'sac': {
    'grade': 2,
    'max': 3,
    'breakdown': {'T2': 1200.0},
    'unofficial_m': 0.0,
  },
  'surfaces': {'natural': 1200.0},
  'way_types': {'path': 1200.0},
  'trails': {'wanderweg': 1200.0},
  'details': {'sac': [], 'surface': [], 'way_type': [], 'trail': []},
  'snap': {'from_m': 3.0, 'to_m': 5.0},
  'warnings': ['snap_far_to'],
};

Map<String, dynamic> _place(String id, String name, {String kind = 'hut'}) => {
  'id': id,
  'kind': kind,
  'name': name,
  'detail': 'alpine_hut',
  'at': [8.1, 46.6],
  'distance_m': 120.0,
  'website': 'https://huette.ch',
};

Map<String, dynamic> _stage({Map<String, dynamic>? start, Map<String, dynamic>? end}) => {
  'start_place': start,
  'end_place': end,
  'accommodation': end == null ? '' : end['name'],
  'totals': _totals,
  'over_max': false,
  'under_min': end == null,
  'earlier': end == null ? null : _place('p0', 'Vorher'),
  'later': null,
  'profile': 'hike',
  'anchors': [
    {'lon': 8.0, 'lat': 46.5},
    {'lon': 8.1, 'lat': 46.6, 'name': 'Hütte'},
  ],
  'legs': [
    _leg([
      [8.0, 46.5, 500],
      [8.1, 46.6, 580],
    ]),
  ],
};

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  test('places in view: bbox and a kind per parameter', () async {
    late Uri asked;
    final api = Api(
      'https://alvyo.test',
      client: MockClient((req) async {
        asked = req.url;
        return _json({
          'places': [
            {
              'id': 'p1',
              'kind': 'hut',
              'name': 'Glecksteinhütte',
              'detail': 'alpine_hut',
              'lon': 8.1,
              'lat': 46.6,
              'website': 'https://gleckstein.ch',
            },
            {'id': 'p2', 'kind': 'campsite', 'name': 'Camping', 'detail': '', 'lon': 8.2, 'lat': 46.7},
          ],
        });
      }),
    );
    final pins = await api.placesInView((west: 7.9, south: 46.55, east: 8.1, north: 46.7), ['hut', 'campsite']);
    expect(asked.path, '/api/v1/places/in-view');
    expect(asked.queryParametersAll, {
      'bbox': ['7.90000,46.55000,8.10000,46.70000'],
      'kind': ['hut', 'campsite'],
    });
    expect(pins.first.name, 'Glecksteinhütte');
    expect(pins.first.website, 'https://gleckstein.ch');
    expect(pins.last.website, '', reason: 'most places have none');
  });

  test('place search sends the centre only inside Switzerland', () async {
    final asked = <Uri>[];
    final api = Api(
      'https://alvyo.test',
      client: MockClient((req) async {
        asked.add(req.url);
        return _json({
          'places': [
            {
              'name': 'Grindelwald',
              'kind': 'pt_stop',
              'detail': 'Zug, Bus',
              'at': [8.03, 46.62],
            },
          ],
        });
      }),
    );
    final found = await api.searchPlaces('grin', near: (lon: 8.0, lat: 46.6));
    expect(asked.last.queryParameters, {'q': 'grin', 'lon': '8.0', 'lat': '46.6'});
    expect(found.single.name, 'Grindelwald');
    expect(found.single.lon, 8.03);
    await api.searchPlaces('grin', near: (lon: 2.35, lat: 48.86));
    expect(asked.last.queryParameters, {'q': 'grin'});
  });

  test('places nearby: kinds comma-separated', () async {
    late Uri asked;
    final api = Api(
      'https://alvyo.test',
      client: MockClient((req) async {
        asked = req.url;
        return _json({
          'places': [_place('p1', 'Hütte')],
        });
      }),
    );
    final places = await api.placesNearby((lon: 8.1, lat: 46.6), kinds: ['hut', 'hotel']);
    expect(asked.queryParameters, {'lon': '8.1', 'lat': '46.6', 'kind': 'hut,hotel'});
    expect(places.single.distanceM, 120);
  });

  test('a leg, and a route saved from anchors and legs as the server sent them', () async {
    final bodies = <String, dynamic>{};
    final api = Api(
      'https://alvyo.test',
      client: MockClient((req) async {
        bodies[req.url.path] = jsonDecode(req.body);
        switch (req.url.path) {
          case '/api/v1/routing/leg':
            return _json(
              _leg([
                [8.0, 46.5, 500],
                [8.01, 46.5, 520],
              ]),
            );
          case '/api/v1/routes':
            return _json({
              'id': 'r9',
              'title': 'Neu',
              'owner_username': 'anna',
              'totals': _totals,
              'tags': <String>[],
              'legs': [bodies['/api/v1/routes']['legs'][0]],
            }, 201);
        }
        return _json({'detail': 'no way'}, 422);
      }),
    );
    final leg = await api.leg((lon: 8.0, lat: 46.5), (lon: 8.01, lat: 46.5), through: (lon: 8.005, lat: 46.51));
    expect(bodies['/api/v1/routing/leg'], {
      'from': {'lon': 8.0, 'lat': 46.5},
      'to': {'lon': 8.01, 'lat': 46.5},
      'profile': 'hike',
      'straight': false,
      'through': {'lon': 8.005, 'lat': 46.51},
    });
    expect(leg.line.last, [8.01, 46.5, 520]);
    expect((leg.durationS, leg.sacGrade, leg.sacMax), (1500, 2, 3));
    expect(leg.warnings, ['snap_far_to']);

    final route = await api.createRoute(
      title: 'Neu',
      profile: 'hike',
      anchors: [
        const Anchor(8.0, 46.5, name: 'Start'),
        const Anchor(8.01, 46.5, straight: true, through: (lon: 8.005, lat: 46.51)),
      ],
      legs: [leg],
    );
    final sent = bodies['/api/v1/routes'] as Map<String, dynamic>;
    expect(sent['anchors'], [
      {'lon': 8.0, 'lat': 46.5, 'name': 'Start'},
      {
        'lon': 8.01,
        'lat': 46.5,
        'straight': true,
        'through': {'lon': 8.005, 'lat': 46.51},
      },
    ]);
    expect(sent['legs'], [leg.json], reason: 'legs go back unchanged');
    expect(sent['visibility'], 'private');
    expect(route.id, 'r9');
    expect(route.line.length, 2);

    await expectLater(
      api.lineAreas(const [
        [8.0, 46.5],
      ]),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 422)),
    );
  });

  test('a journey planned by hours per day, and created from its stages', () async {
    final bodies = <String, dynamic>{};
    final hut = _place('p1', 'Glecksteinhütte');
    final api = Api(
      'https://alvyo.test',
      client: MockClient((req) async {
        bodies[req.url.path] = jsonDecode(req.body);
        switch (req.url.path) {
          case '/api/v1/journeys/plan':
            return _json({
              'stages': [_stage(end: hut), _stage(start: hut)],
              'target_s': 18000,
              'min_s': 14400,
              'max_s': 21600,
            });
          case '/api/v1/journeys':
            return _json({
              'id': 'j9',
              'title': 'Zwei Tage',
              'stage_list': [],
              'totals': _totals,
              'progress': {'stages_done': 0, 'stages_total': 2},
            }, 201);
        }
        return http.Response('', 404);
      }),
    );
    final p = await api.planJourney(
      points: [(lon: 8.0, lat: 46.5), (lon: 8.2, lat: 46.7)],
      minHours: 4,
      maxHours: 6,
      kinds: ['hut'],
    );
    expect(bodies['/api/v1/journeys/plan'], {
      'points': [
        {'lon': 8.0, 'lat': 46.5},
        {'lon': 8.2, 'lat': 46.7},
      ],
      'profile': 'hike',
      'min_hours': 4.0,
      'max_hours': 6.0,
      'kinds': ['hut'],
    });
    expect(p.stages.length, 2);
    expect(p.stages.first.endPlace!.name, 'Glecksteinhütte');
    expect(p.stages.first.startPlace, isNull);
    expect(p.stages.first.earlier!.id, 'p0');
    expect(p.stages.last.underMin, isTrue);
    expect(p.stages.first.totals.durationS, 16200);
    expect(p.stages.first.line.length, 2);

    await api.planJourney(points: [(lon: 8.0, lat: 46.5), (lon: 8.2, lat: 46.7)], days: 2, ends: ['p0']);
    expect(bodies['/api/v1/journeys/plan'], containsPair('ends', ['p0']));
    expect(bodies['/api/v1/journeys/plan'], containsPair('days', 2));
    expect(bodies['/api/v1/journeys/plan'], isNot(contains('min_hours')));

    final j = await api.createJourney(title: 'Zwei Tage', stages: p.stages);
    final stages = (bodies['/api/v1/journeys'] as Map<String, dynamic>)['stages'] as List;
    expect(stages.first, {
      'profile': 'hike',
      'anchors': _stage()['anchors'],
      'legs': jsonDecode(jsonEncode(_stage()['legs'])),
      'accommodation': 'Glecksteinhütte',
      'end_place_id': 'p1',
    });
    expect((stages.last as Map)['start_place_id'], 'p1');
    expect(j.id, 'j9');
  });

  test('suggested ways with their points and days', () async {
    late Map<String, dynamic> body;
    final api = Api(
      'https://alvyo.test',
      client: MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({
          'suggestions': [
            {
              'points': [
                {'lon': 8.0, 'lat': 46.5},
                {'lon': 8.2, 'lat': 46.7},
              ],
              'via': '',
              'proposal': {
                'stages': [_stage()],
                'target_s': 18000,
                'min_s': 0,
                'max_s': 22500,
              },
            },
            {
              'points': [
                {'lon': 8.0, 'lat': 46.5},
                {'lon': 8.3, 'lat': 46.6},
                {'lon': 8.2, 'lat': 46.7},
              ],
              'via': 'Gampel',
              'proposal': {'stages': [], 'target_s': 18000, 'min_s': 0, 'max_s': 22500},
            },
          ],
        });
      }),
    );
    final ways = await api.suggestJourneys(points: [(lon: 8.0, lat: 46.5), (lon: 8.2, lat: 46.7)], hoursPerDay: 5);
    expect(body['hours_per_day'], 5.0);
    expect(body, isNot(contains('ends')));
    expect(ways.length, 2);
    expect(ways.last.via, 'Gampel');
    expect(ways.last.points[1], (lon: 8.3, lat: 46.6));
    expect(ways.first.proposal.stages.single.totals.distanceM, 12000);
  });

  test('discover: filters as parameters, items with their lines', () async {
    late Uri asked;
    final api = Api(
      'https://alvyo.test',
      client: MockClient((req) async {
        asked = req.url;
        return _json({
          'items': [
            {
              'kind': 'journey',
              'id': 'j1',
              'title': 'Via Alpina',
              'owner_username': 'anna',
              'distance_m': 32634.0,
              'ascent_m': 1118.0,
              'duration_s': 34463,
              'longest_s': 17000,
              'sac_grade': 2,
              'sac_max': 3,
              'stages': 2,
              'lines': [
                [
                  [9.5, 47.1],
                  [9.4, 47.0],
                ],
                [
                  [9.4, 47.0],
                  [9.3, 47.0],
                ],
              ],
            },
          ],
          'more': true,
        });
      }),
    );
    final r = await api.discover(
      (west: 9.0, south: 46.9, east: 9.6, north: 47.2),
      kind: 'journey',
      sacMax: 3,
      durationMax: 18000,
    );
    expect(asked.queryParameters, {
      'bbox': '9.0000,46.9000,9.6000,47.2000',
      'kind': 'journey',
      'sac_max': '3',
      'duration_max': '18000',
    });
    expect(r.more, isTrue);
    expect(r.items.single.stages, 2);
    expect(r.items.single.lines.length, 2);
    expect(r.items.single.lines.last.last, [9.3, 47.0]);
  });

  test('a plan with a day over the most per day: the fewest days that fit', () async {
    Future<ApiException> refused(Map<String, dynamic> body) async {
      final api = Api('https://alvyo.test', client: MockClient((req) async => http.Response(jsonEncode(body), 422)));
      try {
        await api.planJourney(points: [(lon: 7.6, lat: 46.8), (lon: 7.7, lat: 46.0)], days: 3, maxHours: 8);
      } on ApiException catch (e) {
        return e;
      }
      fail('not refused');
    }

    Map<String, dynamic> tooLong(int days) => {
      'detail': 'a day would be longer than max_hours',
      'errors': [
        {'location': 'body.max_hours', 'message': 'fewest days that fit', 'value': days},
      ],
    };
    expect((await refused(tooLong(6))).fewestDays, 6);
    expect((await refused(tooLong(0))).fewestDays, 0);
    expect((await refused({'detail': 'no path near one of the points'})).fewestDays, isNull);
  });
}
