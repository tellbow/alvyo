import 'dart:math';
import 'dart:ui';

/// Where the back camera looks, from CoreMotion's attitude with the
/// reference frame «x true north, z vertical» (world: x north, y west,
/// z up). [m] is its rotation matrix, row by row. It turns world into
/// device coordinates (as in Apple's AR sample pARk), so its rows are the
/// device's axes in the world: x to the right of the screen, y to its top,
/// z out of it towards the user (the back camera looks along −z).
class CameraPose {
  const CameraPose(this.m, {required this.fov, this.aspect = 4 / 3, this.accuracy = 2});

  final List<double> m;

  /// The compass's calibration: -1 none, 0 low, 1 medium, 2 high.
  final int accuracy;

  /// The camera's field of view along the picture's long side, in degrees,
  /// and the picture's long side over its short side.
  final double fov, aspect;

  List<double> _axis(int i) => [m[3 * i], m[3 * i + 1], m[3 * i + 2]];

  /// Degrees clockwise from north and above the horizontal of the view's
  /// centre.
  ({double azimuth, double elevation}) get centre {
    final f = _axis(2).map((v) => -v).toList();
    final az = (atan2(-f[1], f[0]) * 180 / pi + 360) % 360;
    return (azimuth: az, elevation: asin(f[2].clamp(-1.0, 1.0)) * 180 / pi);
  }

  /// Where a direction appears on a screen of [size] showing the camera
  /// picture filled (cut to the screen), or null behind the camera. Wider
  /// than high, the screen has turned with the device (the iPad, which
  /// ignores the portrait lock; feedback issue 13): its top is the device's
  /// edge that points up.
  Offset? project(double azimuth, double elevation, Size size) {
    final a = azimuth * pi / 180, e = elevation * pi / 180;
    // World: north, west, up.
    final v = [cos(e) * cos(a), -cos(e) * sin(a), sin(e)];
    double dot(List<double> w) => v[0] * w[0] + v[1] * w[1] + v[2] * w[2];
    final x = dot(_axis(0)), y = dot(_axis(1)), ahead = -dot(_axis(2));
    if (ahead <= 0.01) return null;
    final (right, up) = switch (size.width > size.height) {
      false => (x, y),
      true when m[2] >= 0 => (-y, x), // turned left: the device's right edge on top
      true => (y, -x),
    };
    // The picture's long side runs along the screen's, scaled until it
    // fills the screen.
    final focal = fillScale(size) / 2 / tan(fov * pi / 360);
    return Offset(size.width / 2 + right / ahead * focal, size.height / 2 - up / ahead * focal);
  }

  /// The picture's long side on a screen of [size], in pixels.
  double fillScale(Size size) {
    final long = max(size.width, size.height), short = min(size.width, size.height);
    return max(long, short * aspect);
  }
}
