import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:odysgeh/api.dart';

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
              'user': {'username': 'anna', 'display_name': 'Anna', 'speed_factor': 1.0},
            }),
            200,
            headers: {'set-cookie': 'odysgeh_session=tok123; Path=/; HttpOnly; SameSite=Lax'},
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
    final api = Api('https://odysgeh.test/', client: client);
    final me = await api.login('anna', 'geheim');
    expect(me.username, 'anna');
    expect(api.token, 'tok123');
    final routes = await api.routes();
    expect(routes.single.title, 'Gratweg');
    expect(routes.single.totals.durationS, 1800);
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
    final api = Api('https://odysgeh.test', token: 't', client: client);
    final r = await api.route('r1');
    expect(r.line.length, 4);
    expect(r.line.last, [8.002, 46.5, 1020]);
    await expectLater(api.route('nope'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)));
  });
}
