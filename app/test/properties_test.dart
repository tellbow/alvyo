// Properties that hold for any input, checked on many random ones. Each
// case has its own seed: a failure names it, and `_check` with that seed
// alone replays it.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:alvyo/navigation/tracker.dart';
import 'package:alvyo/navigation/uploads.dart';

const _mPerDegLat = 111320.0;
final _mPerDegLon = _mPerDegLat * cos(46.5 * pi / 180);
final _t0 = DateTime.utc(2026, 9, 23, 8);

/// Runs [property] on [cases] random cases.
void _check(String name, void Function(Random r) property, {int cases = 300, int? seed}) {
  test(name, () {
    for (final s in seed != null ? [seed] : List.generate(cases, (i) => i)) {
      try {
        property(Random(s));
      } on TestFailure catch (e) {
        fail('seed $s: ${e.message}');
      }
    }
  });
}

/// A random walk from 8° E, 46.5° N: [n] steps of up to [stepM] metres.
List<List<double>> _walk(Random r, int n, double stepM) {
  var e = 0.0, north = 0.0, ele = 1500.0;
  return [
    for (var i = 0; i < n; i++)
      () {
        if (i > 0) {
          final a = r.nextDouble() * 2 * pi, d = r.nextDouble() * stepM;
          e += d * cos(a);
          north += d * sin(a);
          ele += (r.nextDouble() - 0.4) * d * 0.3;
        }
        return [8 + e / _mPerDegLon, 46.5 + north / _mPerDegLat, ele];
      }(),
  ];
}

String _text(Random r, int max) {
  const pool = ['a', 'Ü', ' ', '-', '«', '»', '😀', '👩‍👩‍👧', '🇨🇭', '\u{1F3D4}', 'ß', '\t'];
  return List.generate(r.nextInt(max + 1), (_) => pool[r.nextInt(pool.length)]).join();
}

void main() {
  _check('uploadPoints keeps accurate positions in order, 5 m apart, with the first and the last', (r) {
    final pts = _walk(r, r.nextInt(60), 12);
    final fixes = [
      for (final (i, p) in pts.indexed)
        Fix(
          lon: p[0],
          lat: p[1],
          accuracyM: r.nextDouble() * 50,
          time: _t0.add(Duration(seconds: i)),
        ),
    ];
    final out = uploadPoints(fixes);
    final accurate = [
      for (final f in fixes)
        if (f.accuracyM <= 30) f,
    ];
    expect(out.length, lessThanOrEqualTo(accurate.length));
    if (accurate.isEmpty) return expect(out, isEmpty);
    expect(out.first.time, accurate.first.time);
    expect(out.last.time, accurate.last.time);
    for (var i = 1; i < out.length; i++) {
      expect(out[i].time.isAfter(out[i - 1].time), isTrue, reason: 'in order');
      if (i < out.length - 1) {
        final a = Fix(lon: out[i - 1].lon, lat: out[i - 1].lat, time: _t0);
        final b = Fix(lon: out[i].lon, lat: out[i].lat, time: _t0);
        expect(trackLengthM([a, b]), greaterThanOrEqualTo(5), reason: 'point $i');
      }
    }
  });

  _check("hikeTitle fits the server's 120 characters and ends with the date", (r) {
    final route = _text(r, 150);
    final started = _t0.add(Duration(days: r.nextInt(400)));
    final title = hikeTitle(route, started);
    final date = ', ${started.toLocal().day.toString().padLeft(2, '0')}.';
    expect(title.runes.length, lessThanOrEqualTo(120));
    expect(title, contains(date));
    expect(title.endsWith('.${started.toLocal().year}'), isTrue);
    if (route.runes.length + 12 <= 120) expect(title, startsWith(route));
    // No half of a surrogate pair left behind.
    expect(title.runes.every((c) => c < 0xD800 || c > 0xDFFF), isTrue);
  });

  _check('the tracker: done and to go add up, whatever the positions', (r) {
    final line = _walk(r, 2 + r.nextInt(40), 200);
    final ascent = r.nextBool() ? r.nextDouble() * 800 : null;
    final t = RouteTracker(line, durationS: 1 + r.nextInt(30000), speedFactor: 0.5 + r.nextDouble(), ascentM: ascent);
    for (var i = 0; i < 30; i++) {
      // Anywhere near the route, sometimes far off, sometimes inaccurate.
      final p = line[r.nextInt(line.length)];
      final off = r.nextDouble() < 0.2 ? 2000.0 : 80.0;
      final f = Fix(
        lon: p[0] + (r.nextDouble() - 0.5) * off / _mPerDegLon,
        lat: p[1] + (r.nextDouble() - 0.5) * off / _mPerDegLat,
        accuracyM: r.nextDouble() * 100,
        time: _t0.add(Duration(seconds: i * 10)),
      );
      final pr = t.update(f);
      if (pr == null) continue;
      expect(pr.doneM, inInclusiveRange(0, t.lengthM + 1e-6));
      expect(pr.doneM + pr.remainingM, closeTo(t.lengthM, 1e-6));
      expect(pr.remaining.isNegative, isFalse);
      expect(pr.distanceToRouteM, greaterThanOrEqualTo(0));
      expect(pr.ascentDoneM, greaterThanOrEqualTo(0));
      expect(pr.ascentRemainingM, greaterThanOrEqualTo(0));
      if (ascent != null && pr.ascentDoneM > 0) {
        expect(pr.ascentDoneM + pr.ascentRemainingM, closeTo(ascent, 1e-6));
      }
    }
  });

  _check('the tracker: walking the route from start to end gets there without leaving it', (r) {
    // A route that does not cross itself closely: steps ahead within ±60°.
    var e = 0.0, north = 0.0, heading = r.nextDouble() * 2 * pi;
    final line = <List<double>>[];
    for (var i = 0; i < 2 + r.nextInt(30); i++) {
      if (i > 0) {
        heading += (r.nextDouble() - 0.5) * 2 * pi / 3;
        final d = 20 + r.nextDouble() * 300;
        e += d * cos(heading);
        north += d * sin(heading);
      }
      line.add([8 + e / _mPerDegLon, 46.5 + north / _mPerDegLat, 1000 + i * 5.0]);
    }
    final t = RouteTracker(line, durationS: 3600);
    if (t.lengthM < 50) return;
    var last = 0.0;
    Progress? pr;
    // Every 10 m along the line, with a few metres of GPS noise.
    for (var i = 1; i < line.length; i++) {
      final a = line[i - 1], b = line[i];
      final steps = max(1, (_metres(a, b) / 10).ceil());
      for (var k = 1; k <= steps; k++) {
        final f = k / steps;
        pr = t.update(
          Fix(
            lon: a[0] + (b[0] - a[0]) * f + (r.nextDouble() - 0.5) * 6 / _mPerDegLon,
            lat: a[1] + (b[1] - a[1]) * f + (r.nextDouble() - 0.5) * 6 / _mPerDegLat,
            time: _t0,
          ),
        );
        expect(pr!.offRoute, isFalse, reason: 'segment $i');
        expect(pr.doneM, greaterThanOrEqualTo(last - 15), reason: 'went back at segment $i');
        last = max(last, pr.doneM);
      }
    }
    expect(pr!.arrived, isTrue, reason: '${pr.remainingM} m to go');
  });
}

/// Metres between two route points, as the tracker counts them.
double _metres(List<double> a, List<double> b) =>
    trackLengthM([Fix(lon: a[0], lat: a[1], time: _t0), Fix(lon: b[0], lat: b[1], time: _t0)]);
