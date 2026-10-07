import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/watch/importer.dart';
import 'package:alvyo/watch/workouts.dart';

import 'watch_screen_test.dart' show FakeWorkouts;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('watch'));
  tearDown(() => dir.deleteSync(recursive: true));

  Workout hike(String id, DateTime start) =>
      Workout(uuid: id, start: start, end: start.add(const Duration(hours: 2)), hiking: true, source: 'Apple Watch');

  test('automatically: only the hikes since switched on, each once', () async {
    final uploaded = <String>[];
    final api = Api(
      'https://alvyo.test',
      token: 't',
      client: MockClient((req) async {
        uploaded.add((jsonDecode(req.body) as Map<String, dynamic>)['id'] as String);
        return http.Response(jsonEncode({'id': 'r'}), 201, headers: {'content-type': 'application/json'});
      }),
    );
    final since = DateTime.utc(2026, 10, 1);
    final source = FakeWorkouts([
      hike('new', since.add(const Duration(days: 2))),
      hike('old', since.subtract(const Duration(days: 3))),
      hike('indoor', since.add(const Duration(days: 1))), // no track
    ]);
    final importer = WatchImporter(api, source: source, importedFile: File('${dir.path}/imported.json'));

    expect(await importer.importNew(since, (w) => 'Wanderung ${w.uuid}'), 1);
    expect(uploaded, ['watch-new']);
    // Again: nothing new.
    expect(await importer.importNew(since, (w) => ''), 0);
    expect(uploaded, ['watch-new']);
    // Remembered across starts of the app.
    final again = WatchImporter(api, source: source, importedFile: File('${dir.path}/imported.json'));
    expect(await again.importNew(since, (w) => ''), 0);
  });

  test('without Apple Health: nothing', () async {
    final importer = WatchImporter(
      Api('https://alvyo.test'),
      source: FakeWorkouts([hike('w', DateTime.now())], available: false),
      importedFile: File('${dir.path}/imported.json'),
    );
    expect(await importer.importNew(DateTime.utc(2026), (w) => ''), 0);
  });
}
