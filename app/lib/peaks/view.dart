import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'pack.dart';

const _metresPerDegree = 111320.0;
const _earthRadius = 6371000.0;

/// Light bends around the earth a little: distant things look higher.
const _refraction = 0.13;

/// How far summits are named and the skyline drawn.
const maxDistance = 200000.0;

/// Azimuth steps of the skyline.
const skylineBins = 1440; // 0.25°

/// A summit seen from where one stands.
class SeenSummit {
  const SeenSummit(this.summit, this.azimuth, this.elevation, this.distance);
  final Summit summit;

  /// Degrees clockwise from north; degrees above the horizontal; metres.
  final double azimuth, elevation, distance;
}

/// What one sees from a point: the skyline and the summits not hidden
/// behind terrain.
class PeakView {
  const PeakView({required this.eye, required this.skyline, required this.summits});

  /// The eye's height in metres.
  final double eye;

  /// The highest elevation angle in degrees per [skylineBins] of azimuth.
  final Float32List skyline;

  /// The summits in sight, highest first.
  final List<SeenSummit> summits;
}

/// The angle in degrees under which a point at height [h] and distance [d]
/// appears from the eye at height [eye], with the earth's curvature.
double elevationAngle(double h, double d, double eye) =>
    atan2(h - eye - d * d / (2 * _earthRadius) * (1 - _refraction), d) * 180 / pi;

/// [computeView] in the background: some hundred thousand height samples.
/// A top-level function, so the isolate gets only the pack and the point.
Future<PeakView> computeViewInBackground(PeakPack pack, double lon, double lat) =>
    Isolate.run(() => computeView(pack, lon, lat));

/// Computes the view from [lon], [lat] with the eye [above] the ground.
PeakView computeView(PeakPack pack, double lon, double lat, {double above = 2}) {
  final ground = pack.height(lon, lat) ?? 0;
  final eye = ground + above;
  final cosLat = cos(lat * pi / 180);

  // The highest angle along a ray from [from] to [to] metres.
  double highest(double az, double from, double to) {
    final dn = cos(az * pi / 180) / _metresPerDegree, de = sin(az * pi / 180) / (_metresPerDegree * cosLat);
    var best = -90.0;
    for (var d = from; d < to; d += max(50, d * 0.01)) {
      final h = pack.height(lon + d * de, lat + d * dn);
      if (h == null) break;
      final a = elevationAngle(h, d, eye);
      if (a > best) best = a;
    }
    return best;
  }

  final skyline = Float32List(skylineBins);
  for (var i = 0; i < skylineBins; i++) {
    skyline[i] = highest(i * 360 / skylineBins, 50, maxDistance);
  }

  final seen = <SeenSummit>[];
  for (final s in pack.summits) {
    final north = (s.lat - lat) * _metresPerDegree, east = (s.lon - lon) * _metresPerDegree * cosLat;
    final d = sqrt(north * north + east * east);
    if (d < 100 || d > maxDistance) continue;
    final az = (atan2(east, north) * 180 / pi + 360) % 360;
    final el = elevationAngle(s.ele.toDouble(), d, eye);
    // Close terrain is left out (the grid smooths the slope one stands on),
    // and the summit's own flanks: they are lower in the grid than its top.
    if (highest(az, 300, d - max(300, d * 0.03)) > el + 0.1) continue;
    seen.add(SeenSummit(s, az, el, d));
  }
  seen.sort((a, b) => b.summit.ele.compareTo(a.summit.ele));
  return PeakView(eye: eye, skyline: skyline, summits: seen);
}
