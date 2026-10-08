import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'tracker.dart';

/// Whether the app may use the location; asks the first time.
Future<bool> locationAllowed() async {
  if (!await Geolocator.isLocationServiceEnabled()) return false;
  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
  return p == LocationPermission.whileInUse || p == LocationPermission.always;
}

/// GPS positions for hiking: the best accuracy, every 5 m, also while the
/// phone is locked (iOS shows the location indicator).
Stream<Fix> gpsFixes() {
  final settings = defaultTargetPlatform == TargetPlatform.iOS
      ? AppleSettings(
          accuracy: LocationAccuracy.best,
          activityType: ActivityType.fitness,
          distanceFilter: 5,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
        )
      : const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 5);
  return Geolocator.getPositionStream(
    locationSettings: settings,
  ).map((p) => Fix(lon: p.longitude, lat: p.latitude, ele: p.altitude, accuracyM: p.accuracy, time: p.timestamp));
}

/// Where the phone is, when the app may already use the location; never
/// asks. Null without permission or without a fix within a few seconds.
/// With [maxAge], a last known position older than that is not taken (it
/// may be where the train left from).
Future<({double lon, double lat})?> knownPosition({Duration? maxAge}) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    final p = await Geolocator.checkPermission();
    if (p != LocationPermission.whileInUse && p != LocationPermission.always) return null;
    final last = await Geolocator.getLastKnownPosition();
    final fresh = last != null && (maxAge == null || DateTime.now().difference(last.timestamp) <= maxAge);
    final at = fresh
        ? last
        : await Geolocator.getCurrentPosition(
            locationSettings: LocationSettings(
              accuracy: maxAge == null ? LocationAccuracy.low : LocationAccuracy.high,
              timeLimit: Duration(seconds: maxAge == null ? 5 : 15),
            ),
          );
    return (lon: at.longitude, lat: at.latitude);
  } on Object {
    return null; // no fix in time, or no plugin (tests)
  }
}

/// Why fixes stopped coming: waiting for the sky, the location taken away,
/// or switched off.
enum GpsProblem { lost, denied, off }

GpsProblem gpsProblem(Object error) => switch (error) {
  PermissionDeniedException() => GpsProblem.denied,
  LocationServiceDisabledException() => GpsProblem.off,
  _ => GpsProblem.lost,
};
