import 'package:flutter/services.dart';
import 'package:health/health.dart';

import '../navigation/tracker.dart';

/// A hike or walk recorded with the Workout app (Apple Watch or iPhone).
class Workout {
  const Workout({
    required this.uuid,
    required this.start,
    required this.end,
    this.distanceM,
    required this.hiking,
    required this.source,
  });

  final String uuid;
  final DateTime start, end;
  final double? distanceM;

  /// «Hiking» rather than «Outdoor Walk».
  final bool hiking;

  /// The device, e.g. «Adrian's Apple Watch».
  final String source;
}

/// Where workouts come from: Apple Health in the app, a fake in tests.
abstract interface class WorkoutSource {
  /// Asks for access the first time; false when Health is not available.
  /// iOS does not tell whether reading was allowed: then nothing is found.
  Future<bool> authorize();

  /// Hikes and walks of the last [days], newest first.
  Future<List<Workout>> recent({int days = 60});

  /// The GPS track of a workout, in order; empty without one.
  Future<List<Fix>> track(Workout w);
}

/// Workouts from Apple Health.
class HealthWorkouts implements WorkoutSource {
  HealthWorkouts({Health? health}) : _health = health ?? Health();
  final Health _health;

  @override
  Future<bool> authorize() async {
    await _health.configure();
    return _health.requestAuthorization(
      [HealthDataType.WORKOUT, HealthDataType.WORKOUT_ROUTE],
      permissions: [HealthDataAccess.READ, HealthDataAccess.READ],
    );
  }

  @override
  Future<List<Workout>> recent({int days = 60}) async {
    final now = DateTime.now();
    final points = await _health.getHealthDataFromTypes(
      types: [HealthDataType.WORKOUT],
      startTime: now.subtract(Duration(days: days)),
      endTime: now,
    );
    return [
      for (final p in points)
        if (p.value case WorkoutHealthValue(:final workoutActivityType, :final totalDistance)
            when workoutActivityType == HealthWorkoutActivityType.HIKING ||
                workoutActivityType == HealthWorkoutActivityType.WALKING)
          Workout(
            uuid: p.uuid,
            start: p.dateFrom,
            end: p.dateTo,
            distanceM: totalDistance?.toDouble(), // metres
            hiking: workoutActivityType == HealthWorkoutActivityType.HIKING,
            source: p.sourceName,
          ),
    ]..sort((a, b) => b.start.compareTo(a.start));
  }

  /// How long before its workout a route may start. HealthKit only finds
  /// routes that start within the time asked for, and the Watch's can start
  /// seconds before the workout (issue 33).
  static const routeLead = Duration(minutes: 10);

  @override
  Future<List<Fix>> track(Workout w) async {
    final points = await _health.getHealthDataFromTypes(
      types: [HealthDataType.WORKOUT_ROUTE],
      startTime: w.start.subtract(routeLead),
      endTime: w.end,
    );
    // A paused workout has one route per part. Watch routes name no workout:
    // only the positions within its time, not those of one just before.
    return [
      for (final p in points)
        if (p.value case WorkoutRouteHealthValue(
          :final locations,
          :final workoutUuid,
        ) when workoutUuid == null || workoutUuid == w.uuid)
          for (final l in locations)
            if (!l.timestamp.isBefore(w.start) && !l.timestamp.isAfter(w.end))
              Fix(
                lon: l.longitude,
                lat: l.latitude,
                ele: l.altitude,
                accuracyM: l.horizontalAccuracy ?? 10,
                time: l.timestamp,
              ),
    ]..sort((a, b) => a.time.compareTo(b.time));
  }
}

/// Workouts from Health Connect on Android (HealthConnect.kt): hikes and
/// walks that watch apps (Garmin, Samsung, Wear OS …) write there.
class HealthConnectWorkouts implements WorkoutSource {
  /// [ask]: another app's route needs a tap on «Allow» each time unless
  /// always allowed in Health Connect; not asked for when importing in the
  /// background.
  HealthConnectWorkouts({this.ask = true});
  final bool ask;
  static const _channel = MethodChannel('alvyo/health');

  @override
  Future<bool> authorize() async {
    try {
      return await _channel.invokeMethod<bool>('authorize') ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<List<Workout>> recent({int days = 60}) async {
    final list = await _channel.invokeListMethod<Map<Object?, Object?>>('recent', {'days': days}) ?? [];
    return [
      for (final m in list)
        Workout(
          uuid: m['id']! as String,
          start: DateTime.fromMillisecondsSinceEpoch(m['start']! as int),
          end: DateTime.fromMillisecondsSinceEpoch(m['end']! as int),
          hiking: m['hiking']! as bool,
          source: m['source']! as String,
        ),
    ]..sort((a, b) => b.start.compareTo(a.start));
  }

  @override
  Future<List<Fix>> track(Workout w) async {
    final list = await _channel.invokeListMethod<List<Object?>>('route', {'id': w.uuid, 'ask': ask}) ?? [];
    return [
      for (final [lat, lon, ele, accuracy, time] in list)
        Fix(
          lon: (lon! as num).toDouble(),
          lat: (lat! as num).toDouble(),
          ele: (ele as num?)?.toDouble(),
          accuracyM: (accuracy as num?)?.toDouble() ?? 10,
          time: DateTime.fromMillisecondsSinceEpoch(time! as int),
        ),
    ]..sort((a, b) => a.time.compareTo(b.time));
  }
}
