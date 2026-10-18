import 'dart:math';
import 'dart:ui';

/// Dragging a leg onto another way, as on the website
/// (`web/src/lib/planner/dragWays.ts`): a way is [lon, lat] per point.
typedef Way = List<List<double>>;

/// Metres between two points close together (good enough for tens of metres).
double _metres(List<double> a, List<double> b) {
  const k = 111320.0;
  final dx = (a[0] - b[0]) * k * cos((a[1] + b[1]) / 2 * pi / 180);
  return sqrt(dx * dx + pow((a[1] - b[1]) * k, 2));
}

/// Whether [way] is the one [line] takes: nearly all its points lie on it.
bool sameWay(Way way, List<List<double>> line, {double withinM = 25}) {
  if (line.isEmpty) return false;
  final step = max(1, way.length ~/ 40);
  var on = 0, n = 0;
  for (var i = 0; i < way.length; i += step) {
    n++;
    if (line.any((c) => _metres(way[i], c) <= withinM)) on++;
  }
  return on >= 0.9 * n;
}

/// The ways other than the one [line] (the leg as it is) takes, with their
/// index among all.
List<({Way way, int index})> otherWays(List<Way> ways, List<List<double>> line) => [
  for (final (index, way) in ways.indexed)
    if (!sameWay(way, line)) (way: way, index: index),
];

/// The way nearest to [at] on the screen, with its point nearest to it and
/// the distance in pixels; [project] gives a point's screen position.
({({Way way, int index}) way, List<double> point, double px})? nearestWay(
  List<({Way way, int index})> ways,
  Offset at,
  Offset Function(List<double> p) project,
) {
  ({({Way way, int index}) way, List<double> point, double px})? best;
  for (final w in ways) {
    for (final p in w.way) {
      final px = (project(p) - at).distance;
      if (best == null || px < best.px) best = (way: w, point: p, px: px);
    }
  }
  return best;
}

/// The point of [way] farthest from the [others]: ways share stretches, and
/// the leg dragged there must take this way and not another one through the
/// same point.
List<double> distinctPoint(Way way, List<Way> others) {
  var best = way.first;
  var bestM = -1.0;
  for (final p in way) {
    var m = double.infinity;
    for (final o in others) {
      for (final q in o) {
        m = min(m, _metres(p, q));
      }
    }
    if (m > bestM) {
      best = p;
      bestM = m;
    }
  }
  return best;
}
