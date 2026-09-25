import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:alvyo/navigation/hiking_time.dart';
import 'package:alvyo/navigation/tracker.dart';

const _mPerDegLat = 111320.0;
final _mPerDegLon = _mPerDegLat * cos(46.5 * pi / 180);

/// A point [east] and [north] metres from 8° E, 46.5° N.
List<double> at(double east, [double north = 0, double ele = 500]) => [
  8 + east / _mPerDegLon,
  46.5 + north / _mPerDegLat,
  ele,
];

final _t0 = DateTime.utc(2026, 9, 23, 8);
var _seconds = 0;
Fix fix(double east, [double north = 0, double accuracy = 8]) {
  final p = at(east, north);
  return Fix(
    lon: p[0],
    lat: p[1],
    accuracyM: accuracy,
    time: _t0.add(Duration(seconds: _seconds += 10)),
  );
}

void main() {
  group('hiking time', () {
    // The golden values of swiss/hikingtime (from the original JavaScript).
    test('matches the Go implementation', () {
      for (final (d, dh, want) in [
        (1000.0, 0.0, 14.271),
        (1000.0, 100.0, 19.998660671559996),
        (1000.0, -100.0, 14.208582088760002),
        (500.0, 150.0, 24.397023585419948),
        (200.0, 100.0, 17.0),
        (200.0, -100.0, 9.0),
        (100.0, 40.0, 6.8),
        (0.0, 0.0, 0.0),
      ]) {
        expect(segmentMinutes(d, dh), closeTo(want, 1e-9), reason: '$d m, $dh m up');
      }
    });

    test('a mountain profile in 10 m samples', () {
      var total = 0.0;
      double ele(int k) => 800 + 1000 * sin(pi * k * 10 / 12000) + 30 * sin(k * 10 / 150);
      for (var k = 1; k <= 1200; k++) {
        total += segmentMinutes(10, ele(k) - ele(k - 1));
      }
      expect(total, closeTo(338.33480739375005, 1e-6));
    });
  });

  group('route tracker', () {
    // 2 km due east, flat, a point every 20 m.
    final straight = [for (var e = 0.0; e <= 2000; e += 20) at(e)];

    test('progress, remaining time at the hiker\'s pace, arrival', () {
      final tr = RouteTracker(straight, durationS: 1800, speedFactor: 1.2);
      final p = tr.update(fix(500, 10))!;
      expect(p.doneM, closeTo(500, 1));
      expect(p.remainingM, closeTo(1500, 1));
      expect(p.distanceToRouteM, closeTo(10, 0.5));
      expect(p.remaining.inSeconds, closeTo(1800 * 1.2 * 0.75, 2));
      expect(p.offRoute, isFalse);
      expect(p.arrived, isFalse);
      expect(tr.update(fix(1990, 5))!.arrived, isTrue);
    });

    test('off the route after two far positions, back on when close again', () {
      final tr = RouteTracker(straight, durationS: 1800);
      tr.update(fix(300));
      expect(tr.update(fix(320, 80))!.offRoute, isFalse, reason: 'one stray position');
      expect(tr.update(fix(340, 80))!.offRoute, isTrue);
      expect(tr.update(fix(360, 40))!.offRoute, isTrue, reason: 'not close enough yet');
      expect(tr.update(fix(380, 20))!.offRoute, isFalse);
      expect(tr.update(fix(400, 80))!.offRoute, isFalse, reason: 'counting starts again');
    });

    test('inaccurate positions are ignored', () {
      final tr = RouteTracker(straight, durationS: 1800);
      final p = tr.update(fix(300));
      expect(tr.update(fix(900, 0, 120)), same(p));
    });

    test('climbs count for more of the remaining time than flat parts', () {
      final climbThenFlat = [at(0, 0, 500), at(1000, 0, 800), at(2000, 0, 800)];
      final tr = RouteTracker(climbThenFlat, durationS: 3600);
      final p = tr.update(fix(1000))!;
      final climb = segmentMinutes(1000, 300), flat = segmentMinutes(1000, 0);
      expect(p.remaining.inSeconds, closeTo(3600 * flat / (climb + flat), 2));
      expect(p.doneM, closeTo(1000, 1)); // half the distance, well over half the time
    });

    test('the climb done and still to come add up to the route\'s ascent', () {
      // 300 m up, flat, 100 m down, 200 m up again: 500 m of ascent.
      final line = [at(0, 0, 500), at(1000, 0, 800), at(2000, 0, 800), at(2500, 0, 700), at(3500, 0, 900)];
      final tr = RouteTracker(line, durationS: 3600, ascentM: 550); // the server counts a little more
      final start = tr.update(fix(0))!;
      expect(start.ascentDoneM, 0);
      expect(start.ascentRemainingM, closeTo(550, 0.5));
      final half = tr.update(fix(500))!; // half way up the first climb
      expect(half.ascentDoneM, closeTo(150 * 550 / 500, 1));
      expect(half.ascentDoneM + half.ascentRemainingM, closeTo(550, 0.5));
      final downhill = tr.update(fix(2400))!;
      expect(downhill.ascentDoneM, closeTo(300 * 550 / 500, 1), reason: 'descents add nothing');
      expect(tr.update(fix(3500))!.ascentRemainingM, closeTo(0, 0.5));
    });

    test('an out-and-back route does not jump to the other direction', () {
      // 1 km east, then back west 10 m further north (the other side of the path).
      final outAndBack = [for (var e = 0.0; e <= 1000; e += 20) at(e), for (var e = 1000.0; e >= 0; e -= 20) at(e, 10)];
      final tr = RouteTracker(outAndBack, durationS: 3000);
      var last = 0.0;
      for (final (e, n) in [
        (100.0, 5.0),
        (400.0, 5.0),
        (800.0, 5.0),
        (990.0, 5.0),
        (700.0, 5.0),
        (300.0, 5.0),
        (20.0, 5.0),
      ]) {
        final p = tr.update(fix(e, n))!;
        expect(p.doneM, greaterThan(last), reason: 'at $e m east');
        last = p.doneM;
      }
      expect(last, closeTo(1990, 15));
    });

    test('an out-and-back route on the same path goes on forward on the way back', () {
      final there = [for (var e = 0.0; e <= 1000; e += 20) at(e)];
      final tr = RouteTracker([...there, ...there.reversed.skip(1)], durationS: 3000);
      var last = -1.0;
      for (final e in [for (var e = 900.0; e <= 1000; e += 10) e, for (var e = 990.0; e >= 0; e -= 10) e]) {
        final p = tr.update(fix(e, 2))!;
        expect(p.doneM, greaterThan(last), reason: 'at $e m east');
        last = p.doneM;
      }
      expect(last, closeTo(2000, 5));
    });

    test('walking back along the route goes back', () {
      final tr = RouteTracker(straight, durationS: 1800);
      for (var e = 0.0; e <= 600; e += 10) {
        tr.update(fix(e));
      }
      Progress? p;
      for (var e = 590.0; e >= 450; e -= 10) {
        p = tr.update(fix(e));
      }
      expect(p!.doneM, closeTo(450, 10));
      expect(p.offRoute, isFalse);
    });

    test('a loop starts at its start, and arrives at its end', () {
      // 500 m squares: east, north, west, back south to the trailhead.
      final loop = [
        for (var e = 0.0; e < 500; e += 20) at(e),
        for (var n = 0.0; n < 500; n += 20) at(500, n),
        for (var e = 500.0; e > 0; e -= 20) at(e, 500),
        for (var n = 500.0; n >= 0; n -= 20) at(0, n),
      ];
      final tr = RouteTracker(loop, durationS: 1800);
      final first = tr.update(fix(-3, 2))!; // at the trailhead, nearer the loop's last metres
      expect(first.doneM, lessThan(10));
      expect(first.arrived, isFalse);
      Progress? p;
      for (var e = 20.0; e < 500; e += 20) {
        p = tr.update(fix(e));
      }
      for (var n = 0.0; n <= 500; n += 20) {
        p = tr.update(fix(500, n));
      }
      for (var e = 480.0; e >= 0; e -= 20) {
        p = tr.update(fix(e, 500));
      }
      for (var n = 480.0; n >= 0; n -= 20) {
        p = tr.update(fix(0, n));
      }
      expect(p!.arrived, isTrue);
      expect(p.doneM, closeTo(2000, 30));
    });

    test('a shortcut to a later part is followed', () {
      final tr = RouteTracker(straight, durationS: 1800);
      tr.update(fix(100));
      final p = tr.update(fix(1800, 5))!; // beyond the look-ahead
      expect(p.doneM, closeTo(1800, 1));
      expect(p.offRoute, isFalse);
    });
  });
}
