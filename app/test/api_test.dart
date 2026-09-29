import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';

void main() {
  const totals = {
    'distance_m': 1500.0,
    'ascent_m': 120.0,
    'descent_m': 30.0,
    'duration_s': 1800,
    'sac_grade': 2,
    'sac_max': 3,
  };

  test('login keeps the session token and sends it as Bearer', () async {
    final client = MockClient((req) async {
      switch (req.url.path) {
        case '/api/v1/auth/login':
          expect(jsonDecode(req.body), {'login': 'anna', 'password': 'geheim'});
          return http.Response(
            jsonEncode({
              'user': {'id': 'u-anna', 'username': 'anna', 'display_name': 'Anna', 'speed_factor': 1.0},
            }),
            200,
            headers: {'set-cookie': 'alvyo_session=tok123; Path=/; HttpOnly; SameSite=Lax'},
          );
        case '/api/v1/routes':
          expect(req.headers['authorization'], 'Bearer tok123');
          return http.Response(
            jsonEncode({
              'routes': [
                {'id': 'r1', 'title': 'Gratweg', 'owner_username': 'anna', 'totals': totals},
              ],
            }),
            200,
          );
      }
      return http.Response('', 404);
    });
    final api = Api('https://alvyo.test/', client: client);
    final me = await api.login('anna', 'geheim');
    expect(me.username, 'anna');
    expect(api.token, 'tok123');
    expect(api.userId, 'u-anna', reason: 'recordings are kept for this account');
    final routes = await api.routes();
    expect(routes.single.title, 'Gratweg');
    expect(routes.single.totals.durationS, 1800);
  });

  test('the server address is tidied', () {
    expect(Api('alvyo.tellbow.ch').server, 'https://alvyo.tellbow.ch');
    expect(Api(' https://alvyo.tellbow.ch// ').server, 'https://alvyo.tellbow.ch');
    expect(Api('http://localhost:5173').server, 'http://localhost:5173');
  });

  test('route detail joins the legs; errors carry the status', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/api/v1/routes/r1') {
        return http.Response(
          jsonEncode({
            'id': 'r1',
            'title': 'Gratweg',
            'owner_username': 'anna',
            'totals': totals,
            'tags': ['Winter', 'mit Kindern'],
            'legs': [
              {
                'coordinates': [
                  [8.0, 46.5, 1000],
                  [8.001, 46.5, 1010],
                ],
              },
              {
                'coordinates': [
                  [8.001, 46.5, 1010],
                  [8.002, 46.5, 1020],
                ],
              },
            ],
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'detail': 'route not found'}), 404);
    });
    final api = Api('https://alvyo.test', token: 't', client: client);
    final r = await api.route('r1');
    expect(r.line.length, 4);
    expect(r.line.last, [8.002, 46.5, 1020]);
    expect(r.tags, ['Winter', 'mit Kindern']);
    await expectLater(api.route('nope'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)));
  });

  test('journeys: the list, and one with its stages', () async {
    Map<String, dynamic> stage(String id, String title, {Map<String, dynamic>? route, Map<String, dynamic>? extra}) => {
      'id': id,
      'position': 0,
      'title': title,
      'planned_date': null,
      'status': 'planned',
      'done_on': null,
      'transfer_before': null,
      'notes': '',
      'start_place': null,
      'end_place': null,
      'accommodation': '',
      'accommodation_booked': false,
      'route': route,
      'gap': null,
      ...?extra,
    };
    final client = MockClient((req) async {
      switch (req.url.path) {
        case '/api/v1/journeys':
          return http.Response(
            jsonEncode({
              'journeys': [
                {
                  'id': 'j1',
                  'title': 'Via Alpina',
                  'stages': 3,
                  'stages_done': 1,
                  'distance_m': 32634.0,
                  'ascent_m': 1118.0,
                  'duration_s': 34463,
                  'tags': ['Tessin'],
                },
              ],
            }),
            200,
          );
        case '/api/v1/journeys/j1':
          return http.Response(
            jsonEncode({
              'id': 'j1',
              'title': 'Via Alpina',
              'totals': totals,
              'progress': {'stages_done': 1, 'stages_total': 3},
              'stage_list': [
                stage(
                  's1',
                  'Gaflei – Sargans',
                  route: {'id': 'r1', 'totals': totals},
                  extra: {
                    'status': 'done',
                    'start_place': {'name': 'Gaflei, Klinik'},
                    'end_place': {'name': 'Sargans'},
                  },
                ),
                stage(
                  's2',
                  'Sargans – Weisstannen',
                  route: {'id': 'r2', 'totals': totals},
                  extra: {
                    'planned_date': '2026-10-02',
                    'transfer_before': 'pt',
                    'gap': {'metres': 2100.0, 'status': 'transfer'},
                    'accommodation': 'Gasthaus Alpenhof',
                    'accommodation_booked': true,
                  },
                ),
                stage('s3', ''),
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
      }
      return http.Response('', 404);
    });
    final api = Api('https://alvyo.test', token: 't', client: client);
    final list = await api.journeys();
    expect((list.single.title, list.single.stages, list.single.stagesDone), ('Via Alpina', 3, 1));
    expect(list.single.tags, ['Tessin']);

    final j = await api.journey('j1');
    expect((j.stagesDone, j.stagesTotal, j.totals.durationS), (1, 3, 1800));
    final [s1, s2, s3] = j.stages;
    expect((s1.status, s1.startPlace, s1.endPlace, s1.routeId), ('done', 'Gaflei, Klinik', 'Sargans', 'r1'));
    expect(s2.plannedDate, DateTime(2026, 10, 2));
    expect((s2.gapStatus, s2.gapM, s2.transferBefore), ('transfer', 2100.0, 'pt'));
    expect((s2.accommodation, s2.booked), ('Gasthaus Alpenhof', true));
    expect((s3.routeId, s3.totals, s3.gapStatus), (null, null, null));
    final offline = JourneySummary.of(j);
    expect((offline.stages, offline.stagesDone, offline.distanceM), (3, 1, 1500.0));
    expect(offline.tags, isEmpty); // a copy saved before there were tags
  });

  test('a protected area knows when its rule applies', () {
    final winter = ProtectedArea.fromJson({
      'kind': 'wildlife_rest',
      'name': 'Z',
      'binding': true,
      'rule': {'de': 'Zutrittsverbot', 'fr': '', 'it': 'Divieto'},
      'period': {'from': '12-01', 'to': '04-20'},
    });
    expect(winter.appliesOn(DateTime(2027, 1, 15)), isTrue);
    expect(winter.appliesOn(DateTime(2027, 4, 21)), isFalse);
    expect(winter.ruleIn('fr'), 'Zutrittsverbot', reason: 'empty: German');
    expect(winter.ruleIn('it'), 'Divieto');
    final always = ProtectedArea.fromJson({
      'kind': 'hunting_reserve',
      'name': 'R',
      'rule': {'de': 'Teilschutz'},
    });
    expect(always.appliesOn(DateTime(2026, 8, 1)), isTrue);
  });

  test('a point along the way keeps where it is, to be tapped on the map', () {
    final p = Poi.fromJson({
      'kind': 'firepit',
      'name': 'Grillplatz',
      'at': [8.01, 46.66],
      'along_m': 120,
      'off_m': 20,
    });
    final pin = p.toPin(3);
    expect((pin.id, pin.kind, pin.name, pin.lon, pin.lat), ('along-3', 'firepit', 'Grillplatz', 8.01, 46.66));
  });
}
