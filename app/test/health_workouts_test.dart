import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:alvyo/watch/workouts.dart';

/// Apple Health as HealthKit answers: a route only when it starts within the
/// time asked for.
class FakeHealth implements Health {
  FakeHealth(this.routes);
  final List<List<WorkoutRouteLocation>> routes;

  @override
  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    Map<HealthDataType, HealthDataUnit>? preferredUnits,
    required DateTime startTime,
    required DateTime endTime,
    List<RecordingMethod> recordingMethodsToFilter = const [],
  }) async => [
    for (final (i, r) in routes.indexed)
      if (!r.first.timestamp.isBefore(startTime) && r.first.timestamp.isBefore(endTime))
        HealthDataPoint(
          uuid: 'route-$i',
          value: WorkoutRouteHealthValue(locations: r),
          type: HealthDataType.WORKOUT_ROUTE,
          unit: HealthDataUnit.NO_UNIT,
          dateFrom: r.first.timestamp,
          dateTo: r.last.timestamp,
          sourcePlatform: HealthPlatformType.appleHealth,
          sourceDeviceId: 'watch',
          sourceId: 'com.apple.health',
          sourceName: 'Apple Watch',
        ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A position a minute from [from] for each of [minutes], walking north.
List<WorkoutRouteLocation> route(DateTime from, int minutes) => [
  for (var m = 0; m < minutes; m++)
    WorkoutRouteLocation(
      latitude: 46.9 + m * 0.001,
      longitude: 7.4,
      timestamp: from.add(Duration(minutes: m)),
      horizontalAccuracy: 5,
    ),
];

void main() {
  final start = DateTime.utc(2026, 9, 13, 8);
  final w = Workout(
    uuid: 'w',
    start: start,
    end: start.add(const Duration(hours: 2)),
    hiking: true,
    source: 'Apple Watch',
  );

  test('a route that starts a little before its workout (issue 33)', () async {
    final source = HealthWorkouts(health: FakeHealth([route(start.subtract(const Duration(seconds: 5)), 120)]));
    final track = await source.track(w);
    expect(track, hasLength(119)); // the position before the start left out
    expect(track.first.time.isBefore(w.start), isFalse);
  });

  test('not the positions of a workout just before', () async {
    final source = HealthWorkouts(
      health: FakeHealth([route(start.subtract(const Duration(minutes: 8)), 5), route(start, 120)]),
    );
    final track = await source.track(w);
    expect(track, hasLength(120));
    expect(track.first.time, start);
  });
}
