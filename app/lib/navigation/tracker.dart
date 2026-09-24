import 'dart:math';

import 'hiking_time.dart';

/// A GPS position.
class Fix {
  const Fix({required this.lon, required this.lat, this.ele, this.accuracyM = 10, required this.time});

  factory Fix.fromJson(Map<String, dynamic> j) => Fix(
    lon: (j['lon'] as num).toDouble(),
    lat: (j['lat'] as num).toDouble(),
    ele: (j['ele'] as num?)?.toDouble(),
    accuracyM: (j['acc'] as num?)?.toDouble() ?? 10,
    time: DateTime.parse(j['t'] as String),
  );

  final double lon, lat;
  final double? ele;
  final double accuracyM;
  final DateTime time;

  Map<String, dynamic> toJson() => {
    'lon': lon,
    'lat': lat,
    if (ele != null) 'ele': ele,
    'acc': accuracyM,
    't': time.toUtc().toIso8601String(),
  };
}

/// Where the hiker is on the route.
class Progress {
  const Progress({
    required this.doneM,
    required this.remainingM,
    required this.remaining,
    required this.distanceToRouteM,
    required this.offRoute,
    required this.arrived,
    required this.at,
  });

  final double doneM, remainingM;

  /// Walking time for the rest, at the hiker's pace.
  final Duration remaining;
  final double distanceToRouteM;
  final bool offRoute;
  final bool arrived;

  /// The nearest point on the route (lon, lat).
  final List<double> at;
}

const _mPerDeg = 111320.0;

/// The length of a recorded track, from positions accurate to 30 m (so that
/// GPS jitter while standing adds little).
double trackLengthM(List<Fix> fixes) {
  var total = 0.0;
  Fix? prev;
  for (final f in fixes) {
    if (f.accuracyM > 30) continue;
    if (prev != null) total += RouteTracker._distance([prev.lon, prev.lat], [f.lon, f.lat]);
    prev = f;
  }
  return total;
}

/// Matches GPS positions onto a route line (lon, lat, elevation per point).
///
/// The remaining time is the route's own [durationS] (from the server, at pace
/// 1) times the hiker's [speedFactor], shared out along the line by the Swiss
/// hiking time formula, so that climbs count for more than descents.
class RouteTracker {
  RouteTracker(this.line, {required this.durationS, this.speedFactor = 1}) {
    _cumM.add(0);
    _cumMin.add(0);
    for (var i = 1; i < line.length; i++) {
      final d = _distance(line[i - 1], line[i]);
      final dh = line[i].length > 2 && line[i - 1].length > 2 ? line[i][2] - line[i - 1][2] : 0.0;
      _cumM.add(_cumM.last + d);
      _cumMin.add(_cumMin.last + segmentMinutes(d, dh));
    }
  }

  final List<List<double>> line;
  final int durationS;

  /// The hiker's pace (1: as the signposts); known only once online.
  double speedFactor;
  final _cumM = <double>[];
  final _cumMin = <double>[];

  /// Positions farther than this from the route, twice in a row, are off it.
  static const offRouteM = 50.0;

  /// Back on the route when this close again.
  static const backOnRouteM = 30.0;

  /// Positions less accurate than this are ignored.
  static const maxAccuracyM = 75.0;

  /// How far along the route the next position is looked for (from the last
  /// one): a little back, farther ahead. Keeps out-and-back routes from
  /// jumping to the other direction.
  static const _behindM = 200.0, _aheadM = 1500.0;

  double get lengthM => _cumM.last;

  Progress? _last;

  /// Where on the route the last position was; the start before the first,
  /// so that a loop does not begin at its end.
  double _alongM = 0;
  var _farInARow = 0;
  var _off = false;

  Progress? get last => _last;

  /// The progress after [fix]; inaccurate positions keep the last progress.
  Progress? update(Fix fix) {
    if (fix.accuracyM > maxAccuracyM || line.length < 2) return _last;
    var match = _nearest(fix, (_alongM - _behindM, _alongM + _aheadM));
    if (match.distanceM > offRouteM) {
      // Lost within the window: maybe a shortcut to a later part.
      final anywhere = _nearest(fix, null);
      if (anywhere.distanceM < offRouteM) match = anywhere;
    }
    if (!_off) {
      _farInARow = match.distanceM > offRouteM ? _farInARow + 1 : 0;
      _off = _farInARow >= 2;
    } else if (match.distanceM < backOnRouteM) {
      _off = false;
      _farInARow = 0;
    }
    _alongM = match.alongM;

    final share = _cumMin.last == 0 ? 1 - match.alongM / lengthM : 1 - match.minutes / _cumMin.last;
    final remainingM = lengthM - match.alongM;
    return _last = Progress(
      doneM: match.alongM,
      remainingM: remainingM,
      remaining: Duration(seconds: (durationS * speedFactor * share).round()),
      distanceToRouteM: match.distanceM,
      offRoute: _off,
      arrived: remainingM < 30 && match.distanceM < offRouteM,
      at: match.at,
    );
  }

  /// Within the window, going back costs this many metres per metre: on
  /// the way back of an out-and-back route, the way there is just as near.
  static const _backCost = 0.5;

  _Match _nearest(Fix fix, (double, double)? window) {
    final cosLat = cos(fix.lat * pi / 180);
    // Local metres around the fix.
    double x(List<double> p) => (p[0] - fix.lon) * cosLat * _mPerDeg;
    double y(List<double> p) => (p[1] - fix.lat) * _mPerDeg;
    _Match? best;
    var bestScore = double.infinity;
    for (var i = 1; i < line.length; i++) {
      if (window != null && (_cumM[i] < window.$1 || _cumM[i - 1] > window.$2)) continue;
      final ax = x(line[i - 1]), ay = y(line[i - 1]), bx = x(line[i]), by = y(line[i]);
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      final t = len2 == 0 ? 0.0 : ((-ax * dx - ay * dy) / len2).clamp(0.0, 1.0);
      final px = ax + t * dx, py = ay + t * dy;
      final d = sqrt(px * px + py * py);
      final along = _cumM[i - 1] + t * (_cumM[i] - _cumM[i - 1]);
      final score = window == null ? d : d + _backCost * max(0.0, _alongM - along);
      if (score < bestScore) {
        bestScore = score;
        best = _Match(
          distanceM: d,
          alongM: along,
          minutes: _cumMin[i - 1] + t * (_cumMin[i] - _cumMin[i - 1]),
          at: [line[i - 1][0] + t * (line[i][0] - line[i - 1][0]), line[i - 1][1] + t * (line[i][1] - line[i - 1][1])],
        );
      }
    }
    return best ?? _Match(distanceM: double.infinity, alongM: _alongM, minutes: 0, at: line.first);
  }

  static double _distance(List<double> a, List<double> b) {
    final dx = (b[0] - a[0]) * cos((a[1] + b[1]) / 2 * pi / 180) * _mPerDeg;
    final dy = (b[1] - a[1]) * _mPerDeg;
    return sqrt(dx * dx + dy * dy);
  }
}

class _Match {
  _Match({required this.distanceM, required this.alongM, required this.minutes, required this.at});
  final double distanceM, alongM, minutes;
  final List<double> at;
}
