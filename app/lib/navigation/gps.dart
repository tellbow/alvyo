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
Future<({double lon, double lat})?> knownPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    final p = await Geolocator.checkPermission();
    if (p != LocationPermission.whileInUse && p != LocationPermission.always) return null;
    final at =
        await Geolocator.getLastKnownPosition() ??
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 5)),
        );
    return (lon: at.longitude, lat: at.latitude);
  } on Object {
    return null; // no fix in time, or no plugin (tests)
  }
}
