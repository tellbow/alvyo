import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

/// A hike's lines as a thumbnail of its shape, in the accent colour, with
/// the same scale both ways (as `outline` on the website).
class Outline extends StatelessWidget {
  const Outline(this.lines, {super.key, this.width = 72, this.height = 44});
  final List<List<LonLat>> lines;
  final double width, height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: CustomPaint(painter: _OutlinePainter(lines, AlvyoColors.of(context).accent)),
  );
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter(this.lines, this.color);
  final List<List<LonLat>> lines;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = outlinePath(lines, size);
    if (path == null) return;
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_OutlinePainter old) => old.lines != lines || old.color != color;
}

/// The lines fitted into [size] with [pad] around; null without a line.
Path? outlinePath(List<List<LonLat>> lines, Size size, {double pad = 2}) {
  final pts = lines.expand((l) => l).toList();
  if (pts.length < 2) return null;
  // Degrees of longitude are shorter than those of latitude up here.
  final k = math.cos(pts.first.lat * math.pi / 180);
  final xs = pts.map((p) => p.lon * k), ys = pts.map((p) => p.lat);
  final x0 = xs.reduce(math.min), x1 = xs.reduce(math.max);
  final y0 = ys.reduce(math.min), y1 = ys.reduce(math.max);
  // A line straight north or east has no extent the other way to fit.
  double fit(double room, double span) => span > 0 ? room / span : double.infinity;
  final s = math.min(fit(size.width - 2 * pad, x1 - x0), fit(size.height - 2 * pad, y1 - y0));
  if (!s.isFinite) return null;
  final ox = (size.width - (x1 - x0) * s) / 2, oy = (size.height - (y1 - y0) * s) / 2;
  final path = Path();
  for (final line in lines) {
    for (final (i, p) in line.indexed) {
      final x = ox + (p.lon * k - x0) * s, y = size.height - oy - (p.lat - y0) * s;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
  }
  return path;
}
