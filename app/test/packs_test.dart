import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:odysgeh/api.dart';
import 'package:odysgeh/map_style.dart';
import 'package:odysgeh/offline/downloads.dart';
import 'package:odysgeh/offline/packs.dart';

/// A server with one route whose offline map takes one poll to build.
class FakeServer {
  var key = 'route-r1-aaaaaa';
  var polls = 0;
  var downloads = 0;
  var builds = 0;
  final ranges = <String?>[];

  /// Sends only this many bytes of the next download.
  int? breakAfter;

  /// Turns fail, as with a server before them or GraphHopper down.
  var turnsDown = false;
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
      case ('GET', '/api/v1/routes/r1/turns'):
        if (turnsDown) return http.Response(jsonEncode({'detail': 'routing unavailable'}), 503);
        return http.Response(
          jsonEncode({
            'turns': [
              {'along_m': 40.5, 'kind': 'left'},
            ],
          }),
          200,
        );
      case ('POST', '/api/v1/routes/r1/pack'):
        builds++;
        return http.Response(jsonEncode(status()), 200);
      case ('GET', '/api/v1/routes/r1/pack'):
        polls++;
        return http.Response(jsonEncode(status()), 200);
      case ('GET', final p) when p.startsWith('/api/v1/routes/r1/pack/'):
        downloads++;
        final body = files[p.split('/').last]!;
        ranges.add(req.headers['range']);
        if (RegExp(r'^bytes=(\d+)-$').firstMatch(req.headers['range'] ?? '') case final m?) {
          return http.Response.bytes(body.sublist(int.parse(m[1]!)), 206);
        }
        if (breakAfter case final n?) {
          breakAfter = null; // the connection drops once
          return http.Response.bytes(body.sublist(0, n), 200);
        }
        return http.Response.bytes(body, 200);
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
    expect([for (final t in pack.turns!) (t.alongM, t.kind)], [(40.5, 'left')]);
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

  test('a journey kept for offline, apart from the routes', () async {
    final store = PackStore(root);
    expect(await store.savedJourneys(), isEmpty);
    Map<String, dynamic> journey(String id, String title) => {
      'id': id,
      'title': title,
      'totals': {
        'distance_m': 1500.0,
        'ascent_m': 120.0,
        'descent_m': 30.0,
        'duration_s': 1800,
        'sac_grade': 2,
        'sac_max': 3,
      },
      'progress': {'stages_done': 0, 'stages_total': 0},
      'stage_list': <Object>[],
    };
    await store.saveJourney(JourneyDetail.fromJson(journey('j2', 'Zweite')));
    await store.saveJourney(JourneyDetail.fromJson(journey('j1', 'Via Alpina')));
    await store.saveJourney(JourneyDetail.fromJson(journey('j1', 'Via Alpina, neu')));
    expect([for (final j in await store.savedJourneys()) j.title], ['Via Alpina, neu', 'Zweite']);
    expect((await store.savedJourney('j1'))!.title, 'Via Alpina, neu');
    expect(await store.savedJourney('nope'), isNull);
    expect(await store.savedRoutes(), isEmpty);
  });

  test('saved without turns when they cannot be had', () async {
    final server = FakeServer()..turnsDown = true;
    final api = Api('https://odysgeh.test', token: 't', client: server.client);
    final pack = await PackStore(root, poll: Duration.zero).save(api, 'r1', progress: (_, _) {});
    expect(pack.turns, isNull);
    expect(pack.files, hasLength(2));
  });

  test('a broken off download goes on where it stopped', () async {
    final server = FakeServer()..breakAfter = 4;
    final api = Api('https://odysgeh.test', token: 't', client: server.client);
    final store = PackStore(root, poll: Duration.zero);
    await expectLater(store.save(api, 'r1', progress: (_, _) {}), throwsA(isA<ApiException>()));
    expect(await store.saved('r1'), isNull);

    server.polls = 0;
    final pack = await store.save(api, 'r1', progress: (_, _) {});
    expect(File(pack.files['landeskarte']!).readAsStringSync(), 'PMTiles-lk');
    expect(server.ranges, [null, 'bytes=4-', null]);
  });

  test('a save goes on without the screen and is joined when opened again', () async {
    final server = FakeServer();
    final api = Api('https://odysgeh.test', token: 't', client: server.client);
    final downloads = PackDownloads(Future.value(PackStore(root, poll: Duration.zero)));
    final seen = <SaveProgress?>[];
    downloads.progress('r1').addListener(() => seen.add(downloads.progress('r1').value));

    final first = downloads.save(api, 'r1');
    final again = downloads.save(api, 'r1'); // the screen opened again meanwhile
    expect(downloads.running('r1'), same(first));
    expect(identical(first, again), isTrue);
    final pack = await first;
    expect(pack.key, 'route-r1-aaaaaa');
    expect(server.builds, 1);
    expect(downloads.running('r1'), isNull);
    expect(seen.first, (downloading: false, share: 0.0));
    expect(seen.any((p) => p?.downloading ?? false), isTrue);
    expect(downloads.progress('r1').value, isNull);
  });
}
