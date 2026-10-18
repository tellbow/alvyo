import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:alvyo/drag_ways.dart';

// As web/src/lib/planner/dragWays.spec.ts: along 46.66° N, and one bulging
// north to 46.67°.
final Way straight = [
  for (var i = 0; i <= 20; i++) [8 + i * 0.001, 46.66],
];
final Way north = [
  for (var i = 0; i <= 20; i++) [8 + i * 0.001, 46.66 + 0.01 * sin(i / 20 * pi)],
];

void main() {
  test('knows the way the leg takes from the others', () {
    final leg = [
      for (final p in straight) [p[0], p[1] + 0.00005, 500.0], // 5 m off, with heights
    ];
    expect(sameWay(straight, leg), isTrue);
    expect(sameWay(north, leg), isFalse);
    expect(otherWays([straight, north], leg).map((w) => w.index), [1]);
    // A leg not computed yet: every way is another.
    expect(otherWays([straight, north], []), hasLength(2));
  });

  test('finds the way under the finger, in pixels', () {
    // 1° = 10 000 px, y downwards.
    Offset project(List<double> p) => Offset(p[0] * 10000, -p[1] * 10000);
    final ways = otherWays([straight, north], []);
    final top = project(north[10]);
    final hit = nearestWay(ways, top + const Offset(3, 4), project)!;
    expect(hit.way.index, 1);
    expect(hit.point, north[10]);
    expect(hit.px, closeTo(5, 1e-6));
    expect(nearestWay([], top, project), isNull);
  });

  test('sends the point where the chosen way is farthest from the others', () {
    expect(distinctPoint(north, [straight]), north[10]);
    // Sharing its first half with the straight way: a point in the other half.
    final Way half = [...straight.take(11), ...north.skip(11)];
    expect(half.indexOf(distinctPoint(half, [straight])), greaterThan(10));
  });
}
