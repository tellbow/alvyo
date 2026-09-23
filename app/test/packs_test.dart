import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:odysgeh/api.dart';
import 'package:odysgeh/map_style.dart';
import 'package:odysgeh/offline/packs.dart';

/// A server with one route whose offline map takes one poll to build.
class FakeServer {
  var key = 'route-r1-aaaaaa';
  var polls = 0;
  var downloads = 0;
  final files = {'landeskarte': utf8.encode('PMTiles-lk'), 'wanderwege': utf8.encode('PMTiles-ww')};

  Map<String, dynamic> status() => {
    'state': polls < 1 ? 'building' : 'ready',
    'key': key,
    'done': polls < 1 ? 3 : 6,
    'total': 6,
    if (polls >= 1)
      'files': [
        for (final e in files.entries) {'layer': e.key, 'name': '$key-${e.key}.pmtiles', 'bytes': e.value.length},
      ],
  };

  late final client = MockClient((req) async {
    expect(req.headers['authorization'], 'Bearer t');
    switch ((req.method, req.url.path)) {
      case ('GET', '/api/v1/routes/r1'):
        return http.Response(
          jsonEncode({
            'id': 'r1',
            'title': 'Gratweg',
            'owner_username': 'anna',
            'totals': {
              'distance_m': 1500.0,
              'ascent_m': 120.0,
              'descent_m': 30.0,
              'duration_s': 1800,
              'sac_grade': 2,
              'sac_max': 3,
            },
            'legs': [
              {
                'coordinates': [
                  [8.0, 46.5, 1000],
                  [8.001, 46.5, 1010],
                ],
              },
            ],
          }),
          200,
        );
      case ('POST', '/api/v1/routes/r1/pack'):
        return http.Response(jsonEncode(status()), 200);
      case ('GET', '/api/v1/routes/r1/pack'):
        polls++;
        return http.Response(jsonEncode(status()), 200);
      case ('GET', final p) when p.startsWith('/api/v1/routes/r1/pack/'):
        downloads++;
        return http.Response.bytes(files[p.split('/').last]!, 200);
    }
    return http.Response(jsonEncode({'detail': 'not found'}), 404);
  });
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('packs'));
  tearDown(() => root.deleteSync(recursive: true));

  test('saves the built pack with the route; a changed route replaces it', () async {
    final server = FakeServer();
    final api = Api('https://odysgeh.test', token: 't', client: server.client);
    final store = PackStore(root, poll: Duration.zero);
    final steps = <(bool, double)>[];

    final pack = await store.save(api, 'r1', progress: (d, s) => steps.add((d, s)));
    expect(steps.first, (false, 0.5));
    expect(steps.last, (true, 1.0));
    expect(pack.key, 'route-r1-aaaaaa');
    expect(pack.route.title, 'Gratweg');
    expect(File(pack.files['landeskarte']!).readAsStringSync(), 'PMTiles-lk');
    expect(offlineStyle(pack.files), contains('pmtiles://file://'));
    expect((await store.savedRoutes()).single.line.length, 2);

    // The route's line changed: new files, the old ones go.
    server
      ..key = 'route-r1-bbbbbb'
      ..polls = 0;
    final updated = await store.save(api, 'r1', progress: (_, _) {});
    expect((await store.saved('r1'))!.key, 'route-r1-bbbbbb');
    final names = root.listSync(recursive: true).whereType<File>().map((e) => e.uri.pathSegments.last).toSet();
    expect(names, {'manifest.json', 'route-r1-bbbbbb-landeskarte.pmtiles', 'route-r1-bbbbbb-wanderwege.pmtiles'});
    expect(File(updated.files['wanderwege']!).existsSync(), isTrue);

    await store.delete('r1');
    expect(await store.saved('r1'), isNull);
    expect(await store.savedRoutes(), isEmpty);
  });

  test('a cancelled save keeps nothing', () async {
    final server = FakeServer();
    final api = Api('https://odysgeh.test', token: 't', client: server.client);
    final store = PackStore(root, poll: Duration.zero);
    await expectLater(store.save(api, 'r1', progress: (_, _) {}, cancelled: () => true), throwsA(isA<SaveCancelled>()));
    expect(server.downloads, 0);
    expect(await store.saved('r1'), isNull);
  });
}
