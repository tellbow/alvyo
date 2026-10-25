import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart';
import 'package:alvyo/elevation_profile.dart';

void main() {
  test('distances along a line, and the height between samples', () {
    // 0.01° of latitude is 1113 m.
    final d = cumulativeM([
      [8.0, 46.50, 500],
      [8.0, 46.51, 700],
    ]);
    expect(d.last, closeTo(1113, 1));
    expect(heightAt([0, 1000, 2000], [500, 700, 600], 500), 600);
    expect(heightAt([0, 1000, 2000], [500, 700, 600], 1500), 650);
    expect(heightAt([0, 1000, 2000], [500, 700, 600], 5000), 600);
  });

  test('the height axis hugs the heights, in round steps', () {
    // 480 to 1780 m: not from 0 m, where a third of the chart stays empty.
    expect(profileAxis(480, 1780), (lo: 450.0, hi: 1800.0, step: 500.0));
    // Flat: at least 100 m.
    expect(profileAxis(510, 530), (lo: 450.0, hi: 600.0, step: 50.0));
  });

  testWidgets('a finger on the profile reads distance and height', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 452, // 400 px of plot after the labels
            child: ElevationProfile(distances: [0, 2000, 4000], elevations: [500, 900, 700]),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('elevation-readout')), findsNothing);
    final box = tester.getRect(find.byKey(const Key('elevation-profile')));
    // Half way along the plot (48 px labels on the left, 4 px on the right).
    // A drag starts once past the touch slop; it ends half way.
    final gesture = await tester.startGesture(Offset(box.left + 48 + 170, box.center.dy));
    await gesture.moveBy(const Offset(31, 0));
    await gesture.moveBy(const Offset(-1, 0));
    await tester.pump();
    expect(find.text('2.0\u00a0km · 900\u00a0m'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(find.byKey(const Key('elevation-readout')), findsNothing);
  });

  test('the place along a line, and not across the gap between stages', () {
    final points = [
      [8.0, 46.5, 500.0],
      [8.2, 46.7, 900.0],
      [9.0, 47.0, 700.0], // the next stage starts here; no metres between
      [9.2, 47.2, 600.0],
    ];
    const distances = [0.0, 2000.0, 2000.0, 4000.0];
    expect(pointAt(distances, points, 1000), Geographic(lon: 8.1, lat: 46.6));
    expect(pointAt(distances, points, 2000), Geographic(lon: 8.2, lat: 46.7));
    expect(pointAt(distances, points, 3000), Geographic(lon: 9.1, lat: 47.1));
    expect(pointAt(distances, points, 9000), Geographic(lon: 9.2, lat: 47.2));
  });

  testWidgets('dragging along the profile shows the place on the map, and lifting hides it', (tester) async {
    final places = <Geographic?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 452,
            child: ElevationProfile(
              distances: const [0, 2000, 4000],
              elevations: const [500, 900, 700],
              points: const [
                [8.0, 46.5, 500],
                [8.2, 46.7, 900],
                [8.4, 46.9, 700],
              ],
              onPoint: places.add,
            ),
          ),
        ),
      ),
    );
    final box = tester.getRect(find.byKey(const Key('elevation-profile')));
    final gesture = await tester.startGesture(Offset(box.left + 48 + 170, box.center.dy));
    await gesture.moveBy(const Offset(31, 0));
    await gesture.moveBy(const Offset(-1, 0));
    await tester.pump();
    expect(places.last, Geographic(lon: 8.2, lat: 46.7));
    await gesture.up();
    await tester.pump();
    expect(places.last, isNull);
  });
}
