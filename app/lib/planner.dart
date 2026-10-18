import 'package:flutter/foundation.dart';

import 'api.dart';

/// A point of a planned route; [name] is the place it was found as,
/// [alpine]: the leg arriving here uses the alpine profile on a hike route,
/// and [through]: that leg was dragged onto another way, which passes here.
class PlanPoint {
  const PlanPoint(this.id, this.lon, this.lat, [this.name, this.alpine = false, this.through]);
  final int id;
  final double lon, lat;
  final String? name;
  final bool alpine;
  final LonLat? through;
}

/// A leg between two consecutive points: computing, computed, or failed with
/// the HTTP status ([error] 0 without an answer; 422: no path).
class LegSlot {
  LegSlot._({this.leg, this.error});
  final Leg? leg;
  final int? error;
  bool get loading => leg == null && error == null;
}

/// The numbers of the whole route; the hiking time at pace 1.
typedef PlanTotals = ({double distanceM, double ascentM, double descentM, int durationS, int sacGrade, int sacMax});

/// Route planning as on the website: points added, removed and reordered,
/// each leg computed once for its inputs, so a change only asks for the legs
/// it affects. Answers for legs no longer needed are dropped.
class RoutePlanner extends ChangeNotifier {
  RoutePlanner(this.api);
  final Api api;

  List<PlanPoint> _points = const [];
  String _profile = 'hike';
  final _cache = <String, LegSlot>{};
  final _inflight = <Future<void>>{};
  int _nextId = 1;
  bool _disposed = false;

  List<PlanPoint> get points => _points;

  /// A round trip: after the last point back to the start (requirement 69).
  bool get roundTrip => _roundTrip;
  bool _roundTrip = false;

  /// The points the route runs through: with a round trip, the start again
  /// at the end.
  List<PlanPoint> get _route => _roundTrip && _points.length > 1
      ? [..._points, PlanPoint(-1, _points.first.lon, _points.first.lat, _points.first.name)]
      : _points;

  /// hike (up to T3) or alpine (up to T6).
  String get profile => _profile;

  /// The legs between the route's points (with a round trip, the last one
  /// back to the start).
  List<LegSlot> get legs {
    final route = _route;
    return [for (var i = 1; i < route.length; i++) _cache[_key(route[i - 1], route[i])] ?? LegSlot._()];
  }

  List<Leg> get readyLegs => [for (final l in legs) ?l.leg];

  /// Every leg computed: the route can be saved.
  bool get complete => _route.length > 1 && legs.every((l) => l.leg != null);

  PlanTotals get totals {
    double distance = 0, ascent = 0, descent = 0;
    var duration = 0, grade = 0, max = 0;
    for (final l in readyLegs) {
      distance += l.distanceM;
      ascent += l.ascentM;
      descent += l.descentM;
      duration += l.durationS;
      // The hardest leg's grade, and the highest peak among legs of that grade.
      if (l.sacGrade > grade) {
        grade = l.sacGrade;
        max = l.sacMax;
      } else if (l.sacGrade == grade && l.sacMax > max) {
        max = l.sacMax;
      }
    }
    return (distanceM: distance, ascentM: ascent, descentM: descent, durationS: duration, sacGrade: grade, sacMax: max);
  }

  /// The computed legs joined, [lon, lat, ele] per point.
  List<List<double>> get line => [
    for (final (i, l) in readyLegs.indexed) ...(i == 0 || l.line.isEmpty ? l.line : l.line.skip(1)),
  ];

  /// «Start – Ziel» from the names of the first and last point, as far as known.
  String get suggestedTitle => [?_points.firstOrNull?.name, if (_points.length > 1) ?_points.last.name].join(' – ');

  List<Anchor> get anchors {
    final route = _route;
    return [
      for (final (i, p) in route.indexed)
        // A leg kept from the route being changed keeps how it was made.
        switch (i > 0 ? _kept[_key(route[i - 1], p)] : null) {
          final k? when identical(_cache[_key(route[i - 1], p)], k.slot) => Anchor(
            p.lon,
            p.lat,
            name: p.name,
            alpine: p.alpine,
            straight: k.anchor.straight,
            through: k.anchor.through,
          ),
          _ => Anchor(p.lon, p.lat, name: p.name, alpine: p.alpine, through: p.through),
        },
    ];
  }

  /// The legs of a saved route, by their key: kept while their points are.
  final _kept = <String, ({LegSlot slot, Anchor anchor})>{};

  /// Starts from a saved route: its points, and its legs as they are (also
  /// those dragged onto another path or drawn straight), so only changed
  /// legs are computed again.
  void load(String profile, List<Anchor> anchors, List<Leg> legs) {
    _profile = profile;
    _points = [for (final a in anchors) PlanPoint(_nextId++, a.lon, a.lat, a.name, a.alpine, a.through)];
    for (var i = 1; i < _points.length && i - 1 < legs.length; i++) {
      final key = _key(_points[i - 1], _points[i]);
      final slot = LegSlot._(leg: legs[i - 1]);
      _cache[key] = slot;
      _kept[key] = (slot: slot, anchor: anchors[i]);
    }
    _sync();
  }

  /// A new point becomes the destination.
  void add(double lon, double lat, {String? name}) => _change([..._points, PlanPoint(_nextId++, lon, lat, name)]);

  /// «+ Zwischenziel»: a point before the destination; the destination
  /// stays (without one yet, it is added at the end).
  void insertBeforeLast(double lon, double lat, {String? name}) {
    final p = PlanPoint(_nextId++, lon, lat, name);
    _change(_points.length < 2 ? [..._points, p] : [..._points.take(_points.length - 1), p, _points.last]);
  }

  /// Back to the start after the last point, or not.
  void setRoundTrip(bool on) {
    if (on == _roundTrip) return;
    _roundTrip = on;
    _sync();
  }

  void remove(int id) => _change([
    for (final p in _points)
      if (p.id != id) p,
  ]);

  /// A point dragged elsewhere on the map: no longer the place it was
  /// found as, so without its name; only its legs are asked again.
  void move(int id, double lon, double lat) =>
      _change([for (final p in _points) p.id == id ? PlanPoint(p.id, lon, lat, null, p.alpine, p.through) : p]);

  /// A stop at [index], e.g. where a leg's line was dragged to; the leg it
  /// splits loses the way it was dragged onto.
  void insertAt(int index, double lon, double lat) {
    final points = [..._points]..insert(index, PlanPoint(_nextId++, lon, lat));
    if (index + 1 < points.length) {
      final next = points[index + 1];
      points[index + 1] = PlanPoint(next.id, next.lon, next.lat, next.name, next.alpine);
    }
    _change(points);
  }

  /// Leg [index] takes the way that passes [through] (dragged onto it).
  void takeWay(int index, LonLat through) {
    if (index + 1 >= _points.length) return;
    final p = _points[index + 1];
    _change([..._points]..[index + 1] = PlanPoint(p.id, p.lon, p.lat, p.name, p.alpine, through));
  }

  /// Moves the point at [from] to position [to].
  void reorder(int from, int to) {
    if (to < 0 || to >= _points.length || from == to) return;
    final points = [..._points];
    points.insert(to, points.removeAt(from));
    _change(points);
  }

  /// Plans leg [index] with the alpine profile on a hike route (or not).
  void setAlpine(int index, bool alpine) {
    if (index + 1 >= _points.length) return;
    final p = _points[index + 1];
    _change([..._points]..[index + 1] = PlanPoint(p.id, p.lon, p.lat, p.name, alpine, p.through));
  }

  void setProfile(String profile) {
    if (profile == _profile) return;
    _profile = profile;
    _sync();
  }

  /// Asks again for legs that failed for a passing reason.
  void retry() => _sync();

  /// Resolves once no leg is being computed (for tests).
  Future<void> idle() async {
    while (_inflight.isNotEmpty) {
      await Future.wait(_inflight.toList());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _change(List<PlanPoint> points) {
    // The first point has no leg arriving.
    if (points.firstOrNull case final p? when p.alpine || p.through != null) {
      points = [PlanPoint(p.id, p.lon, p.lat, p.name), ...points.skip(1)];
    }
    _points = points;
    _sync();
  }

  /// The profile of the leg arriving at [to].
  String _profileOf(PlanPoint to) => to.alpine ? 'alpine' : _profile;

  String _key(PlanPoint from, PlanPoint to) {
    String p(double v) => v.toStringAsFixed(6);
    final through = switch (to.through) {
      final t? => '@${p(t.lon)},${p(t.lat)}',
      null => '',
    };
    return '${p(from.lon)},${p(from.lat)}>${p(to.lon)},${p(to.lat)}|${_profileOf(to)}$through';
  }

  /// Requests the legs not computed yet; forgets requests no longer needed.
  void _sync() {
    final route = _route;
    final needed = {for (var i = 1; i < route.length; i++) _key(route[i - 1], route[i])};
    _cache.removeWhere((key, slot) => slot.loading && !needed.contains(key));
    for (var i = 1; i < route.length; i++) {
      final from = route[i - 1], to = route[i];
      final key = _key(from, to);
      final cached = _cache[key];
      // Kept, except failures that may pass (no path nearby will not).
      if (cached != null && (cached.error == null || cached.error == 422)) continue;
      final slot = LegSlot._();
      _cache[key] = slot;
      final profile = _profileOf(to);
      late final Future<void> request;
      request = () async {
        LegSlot done;
        try {
          done = LegSlot._(
            leg: await api.leg(
              (lon: from.lon, lat: from.lat),
              (lon: to.lon, lat: to.lat),
              profile: profile,
              through: to.through,
            ),
          );
        } on ApiException catch (e) {
          done = LegSlot._(error: e.status);
        } on Object {
          done = LegSlot._(error: 0);
        }
        _inflight.remove(request);
        // Stale: the points changed meanwhile and the leg is no longer asked for.
        if (_disposed || !identical(_cache[key], slot)) return;
        _cache[key] = done;
        notifyListeners();
      }();
      _inflight.add(request);
    }
    notifyListeners();
  }
}
