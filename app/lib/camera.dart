import 'dart:math';

/// Centre and zoom that show [line] (lon, lat points) in a map of
/// [width]×[height] logical pixels with [padding] on every side.
({double lon, double lat, double zoom}) fitLine(
  List<List<double>> line,
  double width,
  double height, {
  double padding = 48,
  double maxZoom = 16,
}) {
  double x(double lon) => (lon + 180) / 360;
  double y(double lat) {
    final s = sin(lat * pi / 180);
    return 0.5 - log((1 + s) / (1 - s)) / (4 * pi);
  }

  var x0 = double.infinity, x1 = -double.infinity, y0 = double.infinity, y1 = -double.infinity;
  for (final p in line) {
    x0 = min(x0, x(p[0]));
    x1 = max(x1, x(p[0]));
    y0 = min(y0, y(p[1]));
    y1 = max(y1, y(p[1]));
  }
  // MapLibre's world is 512 px wide at zoom 0.
  final w = max(width - 2 * padding, 1), h = max(height - 2 * padding, 1);
  final dx = max(x1 - x0, 1e-9), dy = max(y1 - y0, 1e-9);
  final zoom = min(log(min(w / (dx * 512), h / (dy * 512))) / ln2, maxZoom);
  final cy = (y0 + y1) / 2;
  final lat = 180 / pi * atan(sinh(pi * (1 - 2 * cy)));
  return (lon: (x0 + x1) / 2 * 360 - 180, lat: lat, zoom: zoom);
}

double sinh(double v) => (exp(v) - exp(-v)) / 2;
