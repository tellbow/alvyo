import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('a finger on the profile reads distance and height', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 444, // 400 px of plot after the labels
            child: ElevationProfile(distances: [0, 2000, 4000], elevations: [500, 900, 700]),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('elevation-readout')), findsNothing);
    final box = tester.getRect(find.byKey(const Key('elevation-profile')));
    // Half way along the plot (40 px labels on the left, 4 px on the right).
    // A drag starts once past the touch slop; it ends half way.
    final gesture = await tester.startGesture(Offset(box.left + 40 + 170, box.center.dy));
    await gesture.moveBy(const Offset(31, 0));
    await gesture.moveBy(const Offset(-1, 0));
    await tester.pump();
    expect(find.text('2.0 km · 900 m'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(find.byKey(const Key('elevation-readout')), findsNothing);
  });
}
