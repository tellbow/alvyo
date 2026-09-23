import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:odysgeh/api.dart';
import 'package:odysgeh/navigation/tracker.dart';
import 'package:odysgeh/navigation/uploads.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('recordings'));
  tearDown(() => root.deleteSync(recursive: true));

  void hike(String started, String title, {List<double> accuracies = const [5, 5, 80, 5]}) {
    final t0 = DateTime.parse(started);
    File('${root.path}/done/${started.replaceAll(':', '-')}.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'route_id': 'r1',
          'title': title,
          'started': started,
          'fixes': [
            for (var i = 0; i < accuracies.length; i++)
              {
                'lon': 8.0 + i * 0.001,
                'lat': 46.5,
                'acc': accuracies[i],
                't': t0.add(Duration(minutes: i)).toIso8601String(),
              },
          ],
        }),
      );
  }

  test('uploads finished hikes once online, and drops those the server refuses', () async {
    hike('2026-09-20T08:00:00.000Z', 'Gratweg');
    hike('2026-09-21T08:00:00.000Z', 'Outside');
    var online = false;
    final bodies = <Map<String, dynamic>>[];
    final api = Api(
      'https://odysgeh.test',
      token: 't',
      client: MockClient((req) async {
        if (!online) throw http.ClientException('offline');
        final b = jsonDecode(req.body) as Map<String, dynamic>;
        bodies.add(b);
        return b['title'] == 'Outside, 21.09.2026'
            ? http.Response(jsonEncode({'detail': 'outside'}), 422)
            : http.Response(jsonEncode({'id': 'new'}), 201);
      }),
    );
    List<String> left() => [for (final f in Directory('${root.path}/done').listSync()) f.uri.pathSegments.last];

    expect(await uploadHikes(api, root), 0);
    expect(left(), hasLength(2), reason: 'offline: all kept');

    online = true;
    expect(await uploadHikes(api, root), 1);
    expect(left(), isEmpty);
    final sent = bodies.firstWhere((b) => b['title'] == 'Gratweg, 20.09.2026');
    expect(sent['id'], '2026-09-20T08:00:00.000Z');
    expect(sent['route_id'], 'r1');
    expect((sent['points'] as List).length, 3, reason: 'the inaccurate position is left out');
  });

  test('points closer than 5 m are left out, but not the last', () {
    final t0 = DateTime.utc(2026, 9, 20, 8);
    // Every second 1.3 m east (walking), for 100 s.
    final fixes = [
      for (var i = 0; i <= 100; i++)
        Fix(
          lon: 8 + i * 1.3 / 76_600,
          lat: 46.5,
          time: t0.add(Duration(seconds: i)),
        ),
    ];
    final points = uploadPoints(fixes);
    expect(points.length, inInclusiveRange(25, 27));
    expect(points.first.time, t0);
    expect(points.last.time, t0.add(const Duration(seconds: 100)));
  });
}
