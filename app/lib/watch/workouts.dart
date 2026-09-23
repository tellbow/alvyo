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
  final _health = Health();

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

  @override
  Future<List<Fix>> track(Workout w) async {
    final points = await _health.getHealthDataFromTypes(
      types: [HealthDataType.WORKOUT_ROUTE],
      startTime: w.start,
      endTime: w.end,
    );
    // A paused workout has one route per part.
    return [
      for (final p in points)
        if (p.value case WorkoutRouteHealthValue(
          :final locations,
          :final workoutUuid,
        ) when workoutUuid == null || workoutUuid == w.uuid)
          for (final l in locations)
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
