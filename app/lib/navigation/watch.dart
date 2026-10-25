import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import 'gps.dart';
import 'tracker.dart';

/// A hike as the watch shows it (ios/AlvyoWatch reads the same keys).
class WatchHike {
  const WatchHike({
    required this.title,
    this.routeId,
    required this.paused,
    required this.elapsed,
    required this.line,
    this.position,
    this.progress,
    this.doneM,
    this.turn,
    this.gps,
  });

  final String title;

  /// Null when recording without a route.
  final String? routeId;
  final bool paused;

  /// Hiked so far, without the pauses; the watch counts on from here.
  final Duration elapsed;

  /// The route's line, or the track so far without a route; at most
  /// [WatchLink.maxPoints] points.
  final List<List<double>> line;
  final Fix? position;
  final Progress? progress;

  /// How far it is so far, without a route (on one: [progress]).
  final double? doneM;

  /// The next turn's kind (see Turn) and how far it is.
  final (String, double)? turn;
  final GpsProblem? gps;

  Map<String, Object?> toMap(DateTime now) {
    final p = progress;
    return {
      'title': title,
      'routeId': ?routeId,
      'paused': paused,
      'elapsedS': elapsed.inSeconds,
      'at': now.millisecondsSinceEpoch,
      'line': [for (final q in line) ...q.take(2)],
      if (position case final f?) 'position': [f.lon, f.lat],
      'doneM': ?doneM,
      if (p != null) ...{
        'doneM': p.doneM,
        'remainingM': p.remainingM,
        'remainingS': p.remaining.inSeconds,
        'ascentRemainingM': p.ascentRemainingM,
        'offRoute': p.offRoute,
        'offRouteM': p.distanceToRouteM.round(),
        'arrived': p.arrived,
      },
      if (turn case (final kind, final inM)) ...{'turn': kind, 'turnInM': inM},
      if (gps case final g?) 'gps': g.name,
    };
  }
}

/// What the watch's buttons do on the hike being shown.
class HikeControls {
  const HikeControls({required this.pause, required this.resume, required this.stop});
  final Future<void> Function() pause, resume, stop;
}

/// The Apple Watch app: the hike on the phone's screen goes to the watch
/// (WatchConnectivity, `WatchBridge` in AppDelegate.swift), and the watch's
/// buttons come back. The phone navigates and records; the watch shows
/// and controls.
class WatchLink {
  WatchLink({MethodChannel? channel, bool? enabled})
    : _channel = channel ?? const MethodChannel('alvyo/watch'),
      enabled = enabled ?? Platform.isIOS {
    if (this.enabled) _channel.setMethodCallHandler(_call);
  }

  static final instance = WatchLink();

  final MethodChannel _channel;

  /// Only iOS has the watch app.
  final bool enabled;

  /// Lines sent to the watch are cut down to this many points.
  static const maxPoints = 300;

  /// The hike on screen, set by its screen while it is open.
  HikeControls? controls;

  /// Starts a hike asked for on the watch: on a route, or without one
  /// (null). Set by the home screen.
  Future<void> Function(String? routeId, String title)? onStart;

  /// The tours the watch offers to start (as the record button's list).
  Future<void> tours(List<RouteSummary> routes, double pace) => _send('tours', [
    for (final r in routes.take(50))
      {'id': r.id, 'title': r.title, 'distanceM': r.totals.distanceM, 'durationS': (r.totals.durationS * pace).round()},
  ]);

  /// The hike now; null once it ended.
  Future<void> show(WatchHike? hike) => _send('hike', hike?.toMap(DateTime.now()));

  /// A start asked for on the watch while the phone was locked or the app
  /// not open: done now that it is.
  Future<void> startPending() async {
    if (!enabled) return;
    final Object? pending;
    try {
      pending = await _channel.invokeMethod<Object?>('pendingStart');
    } on Object {
      return; // no watch bridge (an older build)
    }
    if (pending case {'title': final String title} && final Map m) {
      unawaited(onStart?.call(m['routeId'] as String?, title));
    }
  }

  Future<void> _send(String method, Object? args) async {
    if (!enabled) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on Object catch (e) {
      debugPrint('watch: $e'); // no watch: nothing to show
    }
  }

  /// A button on the watch; the answer goes back to it.
  Future<String> _call(MethodCall call) async {
    switch (call.method) {
      case 'start':
        final start = onStart;
        if (start == null) return 'notReady'; // logged out
        if (controls != null) return 'busy';
        final args = call.arguments as Map;
        // Not awaited: the watch waits only for the answer, not the hike.
        unawaited(start(args['routeId'] as String?, args['title'] as String? ?? ''));
        return 'ok';
      case 'pause' || 'resume' || 'stop':
        final c = controls;
        if (c == null) return 'none';
        await switch (call.method) {
          'pause' => c.pause(),
          'resume' => c.resume(),
          _ => c.stop(),
        };
        return 'ok';
    }
    throw MissingPluginException(call.method);
  }
}

/// [line] with at most [maxPoints] points (Douglas–Peucker, the tolerance
/// doubled from 2 m until it fits), for the watch's small screen.
List<List<double>> simplifyLine(List<List<double>> line, int maxPoints) {
  if (line.length <= maxPoints) return line;
  final cosLat = cos(line.first[1] * pi / 180);
  const mPerDeg = 111320.0;
  // Distance of p from the segment a–b, in metres.
  double off(List<double> p, List<double> a, List<double> b) {
    final ax = (a[0] - p[0]) * cosLat * mPerDeg, ay = (a[1] - p[1]) * mPerDeg;
    final bx = (b[0] - p[0]) * cosLat * mPerDeg, by = (b[1] - p[1]) * mPerDeg;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : ((-ax * dx - ay * dy) / len2).clamp(0.0, 1.0);
    final x = ax + t * dx, y = ay + t * dy;
    return sqrt(x * x + y * y);
  }

  for (var tolerance = 2.0; ; tolerance *= 2) {
    final keep = List.filled(line.length, false)
      ..first = true
      ..last = true;
    final stack = [(0, line.length - 1)];
    while (stack.isNotEmpty) {
      final (from, to) = stack.removeLast();
      var worst = -1.0, at = -1;
      for (var i = from + 1; i < to; i++) {
        final d = off(line[i], line[from], line[to]);
        if (d > worst) (worst, at) = (d, i);
      }
      if (worst > tolerance) {
        keep[at] = true;
        stack
          ..add((from, at))
          ..add((at, to));
      }
    }
    final out = [
      for (var i = 0; i < line.length; i++)
        if (keep[i]) line[i],
    ];
    if (out.length <= maxPoints) return out;
  }
}
