// The upload queue against a server that fails at random, as phones meet it:
// offline, errors, logged out, a refusal, an answer lost after the hike was
// taken. Whatever happens, no hike is lost, none goes to another account,
// and once the server works every hike gets there. A failure names its
// seed; `_seeds` with that one alone replays it.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/navigation/tracker.dart';
import 'package:alvyo/navigation/uploads.dart';

final _seeds = List.generate(150, (i) => i);
const _users = [null, 'u-anna', 'u-bea'];

enum _Answer { ok, lostAfterTaken, offline, error, loggedOut, never, notNow }

void main() {
  for (final seed in _seeds) {
    test('seed $seed', () async {
      final r = Random(seed);
      final root = Directory.systemTemp.createTempSync('recordings');
      addTearDown(() => root.deleteSync(recursive: true));
      final done = Directory('${root.path}/done')..createSync();

      // The hikes on the phone: some another account's, some too short to
      // send, one unreadable now and then.
      final owners = <String, String?>{}; // by id (its start)
      final paths = <String, String>{}; // by id
      final sendable = <String>{};
      final unreadable = <String>{};
      for (var h = 0; h < 1 + r.nextInt(6); h++) {
        final started = DateTime.utc(2026, 9, 1 + h, 8).toIso8601String();
        final file = File('${done.path}/${started.replaceAll(':', '-')}.json');
        if (r.nextInt(10) == 0) {
          file.writeAsStringSync('{"started":');
          unreadable.add(file.path);
          continue;
        }
        final owner = _users[r.nextInt(_users.length)];
        final fixes = [
          for (var i = 0; i < r.nextInt(5); i++)
            Fix(
              lon: 8 + i * 0.001,
              lat: 46.5,
              accuracyM: r.nextInt(4) == 0 ? 80 : 5,
              time: DateTime.parse(started).add(Duration(minutes: i)),
            ),
        ];
        file.writeAsStringSync(
          jsonEncode({
            'title': 'Weg $h',
            'owner': ?owner,
            'started': started,
            'fixes': [for (final f in fixes) f.toJson()],
          }),
        );
        owners[started] = owner;
        paths[started] = file.path;
        if (uploadPoints(fixes).length >= 2) sendable.add(started);
      }

      final taken = <String, String>{}; // hike id → the route the server made
      final refused = <String>{}; // the server can never take these
      Set<String> left() => {
        for (final MapEntry(key: id, value: path) in paths.entries)
          if (File(path).existsSync()) id,
      };

      Future<void> round(String? user, _Answer Function() answer) async {
        final api = Api(
          'https://alvyo.test',
          token: 't',
          userId: user,
          client: MockClient((req) async {
            final id = (jsonDecode(req.body) as Map<String, dynamic>)['id'] as String;
            final owner = owners[id];
            expect(owner == null || owner == user, isTrue, reason: '$id of $owner sent as $user');
            expect(sendable, contains(id), reason: 'too short to send');
            switch (answer()) {
              case _Answer.ok:
                taken.putIfAbsent(id, () => 'route-$id'); // the server takes a hike once
                return http.Response(jsonEncode({'id': taken[id]}), 201);
              case _Answer.lostAfterTaken:
                taken.putIfAbsent(id, () => 'route-$id');
                throw http.ClientException('connection reset');
              case _Answer.offline:
                throw http.ClientException('offline');
              case _Answer.error:
                return http.Response('', 502);
              case _Answer.loggedOut:
                return http.Response(jsonEncode({'detail': 'unauthorized'}), 401);
              case _Answer.never:
                refused.add(id);
                return http.Response(jsonEncode({'detail': 'the hike leaves Switzerland and Liechtenstein'}), 422);
              case _Answer.notNow:
                return http.Response(jsonEncode({'detail': 'validation failed'}), 422);
            }
          }),
        );
        final before = left();
        Map<String, String?>? routes;
        try {
          routes = await uploadHikes(api, root);
        } on ApiException catch (e) {
          expect(e.status, 401, reason: 'only a logout stops the round');
        }
        final after = left();
        for (final id in before.difference(after)) {
          expect(
            taken.containsKey(id) || refused.contains(id) || !sendable.contains(id),
            isTrue,
            reason: '$id deleted, but the server does not have it',
          );
        }
        for (final MapEntry(key: id, value: route) in (routes ?? {}).entries) {
          expect(after, isNot(contains(id)), reason: '$id answered but kept');
          expect(route, route == null ? isNull : taken[id], reason: id);
        }
        for (final path in unreadable) {
          expect(File(path).existsSync() || File('$path.bad').existsSync(), isTrue, reason: 'unreadable lost');
        }
      }

      // Rounds with a server that fails at random, as whoever is logged in.
      for (var i = 0; i < 1 + r.nextInt(8); i++) {
        await round(_users[r.nextInt(_users.length)], () => _Answer.values[r.nextInt(_Answer.values.length)]);
      }
      // Then the server works: every account's hikes get there.
      for (final user in _users.skip(1)) {
        await round(user, () => _Answer.ok);
      }
      expect(left(), isEmpty, reason: 'left on the phone');
      for (final id in sendable) {
        expect(taken.containsKey(id) || refused.contains(id), isTrue, reason: '$id never got there');
      }
      for (final path in unreadable) {
        expect(File('$path.bad').existsSync(), isTrue, reason: 'unreadable not set aside');
      }
    });
  }
}
