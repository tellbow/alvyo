import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/navigation/live.dart';
import 'package:alvyo/navigation/recording.dart';
import 'package:alvyo/navigation/tracker.dart';

/// The server, reachable unless [offline].
class FakeLive {
  var offline = false;
  var status = 204;
  final batches = <List<dynamic>>[];
  final ended = <String>[];

  late final api = Api(
    'https://alvyo.test',
    token: 't',
    client: MockClient((req) async {
      if (offline) throw const SocketException('no connection');
      if (req.url.path.endsWith('/positions')) {
        if (status != 204) return http.Response(jsonEncode({'detail': 'the hike has ended'}), status);
        batches.add((jsonDecode(req.body) as Map<String, dynamic>)['points'] as List);
        return http.Response('', 204);
      }
      if (req.url.path.endsWith('/end')) {
        ended.add(req.url.pathSegments[req.url.pathSegments.length - 2]);
        return http.Response('', 204);
      }
      return http.Response('', 404);
    }),
  );
}

void main() {
  final t0 = DateTime.utc(2026, 9, 26, 8);
  Fix at(int seconds) => Fix(
    lon: 8 + seconds * 1e-5,
    lat: 46.6,
    time: t0.add(Duration(seconds: seconds)),
  );

  test('positions: one a minute, sent every 5 minutes, kept while offline', () async {
    final server = FakeLive();
    final live = LiveSender(server.api, 'l1');
    await live.add(at(0)); // the first goes at once
    expect(server.batches, hasLength(1));
    for (var s = 10; s < 300; s += 10) {
      await live.add(at(s));
    }
    expect(server.batches, hasLength(1), reason: 'not yet 5 minutes');
    expect(live.pending, 5, reason: 'one a minute, the latest of each');
    await live.add(at(300));
    expect(server.batches, hasLength(2));
    expect(server.batches[1], hasLength(5)); // slots from 10, 70, 130, 190 and 250 s
    expect(live.pending, 0);

    // Offline: kept, tried again a minute later, sent once back.
    server.offline = true;
    for (var s = 310; s <= 900; s += 10) {
      await live.add(at(s));
    }
    expect(live.pending, greaterThan(5));
    server.offline = false;
    await live.add(at(960));
    expect(server.batches, hasLength(3));
    expect(live.pending, 0);
    expect(server.batches[2].last['lon'], closeTo(8 + 960e-5, 1e-9));
  });

  test('a share ended elsewhere stops sending', () async {
    final server = FakeLive()..status = 409;
    final live = LiveSender(server.api, 'l1');
    await live.add(at(0));
    expect(live.pending, 0);
  });

  test('a request that hangs does not stop the sending for the rest of the hike', () async {
    final batches = <List<dynamic>>[];
    var hang = true;
    final api = Api(
      'https://alvyo.test',
      token: 't',
      client: MockClient((req) async {
        if (hang) return Completer<http.Response>().future; // weak reception: no answer, ever
        batches.add((jsonDecode(req.body) as Map<String, dynamic>)['points'] as List);
        return http.Response('', 204);
      }),
    );
    final live = LiveSender(api, 'l1', timeout: const Duration(milliseconds: 50));
    unawaited(live.add(at(0)));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    hang = false;
    await live.add(at(60)); // a minute later: tried again
    expect(batches, hasLength(1));
    expect(batches.single, hasLength(2));
    expect(live.pending, 0);
  });

  test('a batch the server refuses is not sent again and again', () async {
    final server = FakeLive()..status = 422;
    final live = LiveSender(server.api, 'l1');
    await live.add(at(0));
    expect(live.pending, 0);
    server.status = 204;
    await live.add(at(300));
    expect(server.batches.single, hasLength(1), reason: 'only the new position');
  });

  test('a position that came while sending waits for the next time', () async {
    final gate = Completer<void>();
    final batches = <List<dynamic>>[];
    final api = Api(
      'https://alvyo.test',
      token: 't',
      client: MockClient((req) async {
        await gate.future;
        batches.add((jsonDecode(req.body) as Map<String, dynamic>)['points'] as List);
        return http.Response('', 204);
      }),
    );
    final live = LiveSender(api, 'l1');
    final sending = live.add(at(0));
    await live.add(at(20)); // the same minute: takes the place of the one being sent
    gate.complete();
    await sending;
    expect(batches.single.single['lon'], closeTo(8, 1e-9));
    expect(live.pending, 1, reason: 'the newer position of the minute is still to be sent');
  });

  test('ending with a request that hangs is sent later, and does not hold up finishing', () async {
    final root = Directory.systemTemp.createTempSync('live');
    addTearDown(() => root.deleteSync(recursive: true));
    final api = Api('https://alvyo.test', token: 't', client: MockClient((_) => Completer<http.Response>().future));
    final outbox = LiveOutbox(root, timeout: const Duration(milliseconds: 50));
    await outbox.end(api, 'l1');
    expect(await outbox.flush(api), 1);
  });

  test('ending while offline is sent later, so nobody is alerted', () async {
    final root = Directory.systemTemp.createTempSync('live');
    addTearDown(() => root.deleteSync(recursive: true));
    final server = FakeLive()..offline = true;
    final outbox = LiveOutbox(root);
    await outbox.end(server.api, 'l1');
    expect(server.ended, isEmpty);
    expect(await outbox.flush(server.api), 1, reason: 'still offline');
    server.offline = false;
    expect(await outbox.flush(server.api), 0);
    expect(server.ended, ['l1']);
    expect(await outbox.flush(server.api), 0);
    expect(server.ended, ['l1'], reason: 'once');
  });

  test('a resumed hike goes on sharing', () async {
    final root = Directory.systemTemp.createTempSync('recordings');
    addTearDown(() => root.deleteSync(recursive: true));
    final rec = await Recording.start(root, routeId: 'r1', title: 'Gratweg', owner: 'u1');
    await rec.setLive('l1', t0.add(const Duration(hours: 5)));
    final resumed = (await Recording.active(root))!;
    expect((resumed.liveId, resumed.expectedEnd), ('l1', t0.add(const Duration(hours: 5))));
  });
}
