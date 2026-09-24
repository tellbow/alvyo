import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odysgeh/navigation/recording.dart';
import 'package:odysgeh/navigation/tracker.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('recordings'));
  tearDown(() => root.deleteSync(recursive: true));

  final t0 = DateTime.utc(2026, 9, 23, 8);
  // About 111 m north per step.
  Fix fix(int i, {double acc = 5}) => Fix(
    lon: 8,
    lat: 46.5 + i * 0.001,
    accuracyM: acc,
    time: t0.add(Duration(minutes: i)),
  );

  test('positions survive the app being stopped; finishing keeps the hike for uploading', () async {
    final rec = await Recording.start(root, routeId: 'r1', title: 'Gratweg', now: t0);
    await rec.add(fix(1));
    await rec.add(fix(2));
    expect(() => Recording.start(root, routeId: 'r2', title: 'Other'), throwsStateError);

    // The app is started again: the same recording, with its positions.
    final resumed = (await Recording.active(root))!;
    expect(resumed.routeId, 'r1');
    expect(resumed.started, t0);
    await resumed.add(fix(3));
    expect((await resumed.fixes()).map((f) => f.lat), [46.501, 46.502, 46.503]);

    final file = await resumed.finish();
    expect(await Recording.active(root), isNull);
    final saved = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(saved['route_id'], 'r1');
    expect(saved['started'], '2026-09-23T08:00:00.000Z');
    expect((saved['fixes'] as List).length, 3);
    expect(
      Fix.fromJson((saved['fixes'] as List).last as Map<String, dynamic>).time,
      t0.add(const Duration(minutes: 3)),
    );
  });

  test('positions written at the same moment all arrive whole', () async {
    final rec = await Recording.start(root, routeId: 'r1', title: 'Gratweg', now: t0);
    final other = (await Recording.active(root))!; // a second screen on the same hike
    await Future.wait([for (var i = 0; i < 50; i++) (i.isEven ? rec : other).add(fix(i))]);
    final lats = (await rec.fixes()).map((f) => f.lat).toList();
    expect(lats, hasLength(50));
    expect(lats.toSet(), hasLength(50));
  });

  test('a line cut off when the app stopped does not lose the hike', () async {
    final rec = await Recording.start(root, routeId: 'r1', title: 'Gratweg', now: t0);
    await rec.add(fix(1));
    await rec.add(fix(2));
    File('${root.path}/active.jsonl').writeAsStringSync('{"lon":8,"lat":46.5', mode: FileMode.append);
    final resumed = (await Recording.active(root))!;
    expect(await resumed.fixes(), hasLength(2));
    await resumed.add(fix(3)); // on a line of its own
    expect(await resumed.fixes(), hasLength(3));
    final saved = jsonDecode(await (await resumed.finish()).readAsString()) as Map<String, dynamic>;
    expect(saved['fixes'], hasLength(3));
    expect(await Recording.active(root), isNull);
  });

  test('two starts at once: one recording', () async {
    final results = await Future.wait([
      for (final id in ['r1', 'r2'])
        Recording.start(root, routeId: id, title: id).then<Object>((r) => r, onError: (Object e) => e),
    ]);
    expect(results.whereType<Recording>(), hasLength(1));
    expect(results.whereType<StateError>(), hasLength(1));
  });

  test('the track length leaves out inaccurate positions', () {
    final fixes = [fix(0), fix(1), fix(5, acc: 80), fix(2)];
    expect(trackLengthM(fixes), closeTo(2 * 111.3, 1));
  });
}
