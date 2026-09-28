import 'dart:math';

import 'package:flutter/material.dart';

import 'format.dart';

const _mPerDeg = 111320.0;

/// Cumulative distance in metres along [line] (lon, lat, … per point).
List<double> cumulativeM(List<List<double>> line) {
  final out = <double>[0];
  for (var i = 1; i < line.length; i++) {
    final a = line[i - 1], b = line[i];
    final dx = (b[0] - a[0]) * cos((a[1] + b[1]) / 2 * pi / 180) * _mPerDeg;
    final dy = (b[1] - a[1]) * _mPerDeg;
    out.add(out.last + sqrt(dx * dx + dy * dy));
  }
  return out;
}

/// The height [m] metres along a profile, between its samples.
double heightAt(List<double> distances, List<double> elevations, double m) {
  final i = distances.indexWhere((d) => d >= m);
  if (i <= 0) return elevations[i < 0 ? elevations.length - 1 : 0];
  final span = distances[i] - distances[i - 1];
  final t = span == 0 ? 0.0 : (m - distances[i - 1]) / span;
  return elevations[i - 1] + t * (elevations[i] - elevations[i - 1]);
}

/// The height axis of a profile: from a little below the lowest to a little
/// above the highest point (at least 100 m, so that flat routes look flat),
/// with grid lines every [step] metres within.
({double lo, double hi, double step}) profileAxis(double lowest, double highest) {
  var lo = lowest, hi = highest;
  if (hi - lo < 100) {
    final mid = (hi + lo) / 2;
    lo = mid - 50;
    hi = mid + 50;
  }
  lo = (lo / 50).floorToDouble() * 50;
  hi = (hi / 50).ceilToDouble() * 50;
  return (lo: lo, hi: hi, step: _niceStep((hi - lo) / 3));
}

/// 10, 20, 25, 50, 100 … metres between grid lines.
double _niceStep(double raw) {
  for (final s in [10.0, 20.0, 25.0, 50.0, 100.0, 200.0, 250.0, 500.0, 1000.0]) {
    if (raw <= s) return s;
  }
  return 1000;
}

/// Height over distance of a route or journey. A finger on it reads the
/// distance and height there; [markerM] marks a place (where the hiker is).
class ElevationProfile extends StatefulWidget {
  const ElevationProfile({
    super.key,
    required this.distances,
    required this.elevations,
    this.markerM,
    this.breaks = const [],
    this.height = 110,
  });

  /// Of a line of lon, lat, elevation per point.
  factory ElevationProfile.ofLine(List<List<double>> line, {Key? key, double? markerM, double height = 110}) =>
      ElevationProfile(
        key: key,
        distances: cumulativeM(line),
        elevations: [for (final p in line) p.length > 2 ? p[2] : 0],
        markerM: markerM,
        height: height,
      );

  final List<double> distances, elevations;
  final double? markerM;

  /// Indexes where a stage starts (journeys), drawn as thin lines.
  final List<int> breaks;
  final double height;

  @override
  State<ElevationProfile> createState() => _ElevationProfileState();
}

class _ElevationProfileState extends State<ElevationProfile> {
  /// Where a finger is, in metres along.
  double? _touchM;

  double get _lengthM => widget.distances.isEmpty ? 0 : widget.distances.last;

  void _touch(Offset local, double width) {
    if (_lengthM <= 0) return;
    final plot = _ProfilePainter.plotRect(Size(width, widget.height));
    final m = ((local.dx - plot.left) / plot.width).clamp(0.0, 1.0) * _lengthM;
    setState(() => _touchM = m);
  }

  double _eleAt(double m) => heightAt(widget.distances, widget.elevations, m);

  @override
  Widget build(BuildContext context) {
    if (widget.distances.length < 2) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme.labelSmall!;
    final touchM = _touchM;
    return LayoutBuilder(
      builder: (context, size) => GestureDetector(
        key: const Key('elevation-profile'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _touch(d.localPosition, size.maxWidth),
        onHorizontalDragStart: (d) => _touch(d.localPosition, size.maxWidth),
        onHorizontalDragUpdate: (d) => _touch(d.localPosition, size.maxWidth),
        onHorizontalDragEnd: (_) => setState(() => _touchM = null),
        onTapUp: (_) => setState(() => _touchM = null),
        child: Stack(
          children: [
            CustomPaint(
              size: Size(size.maxWidth, widget.height),
              painter: _ProfilePainter(
                distances: widget.distances,
                elevations: widget.elevations,
                breaks: widget.breaks,
                markerM: widget.markerM,
                touchM: touchM,
                line: scheme.primary,
                fill: scheme.primary.withValues(alpha: 0.15),
                grid: scheme.outlineVariant,
                marker: const Color(0xFF2563EB),
                label: text.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            if (touchM != null)
              Positioned(
                top: 0,
                right: 0,
                child: Text(
                  key: const Key('elevation-readout'),
                  '${formatDistance(touchM)} · ${formatHeight(_eleAt(touchM))}',
                  style: text.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProfilePainter extends CustomPainter {
  _ProfilePainter({
    required this.distances,
    required this.elevations,
    required this.breaks,
    required this.markerM,
    required this.touchM,
    required this.line,
    required this.fill,
    required this.grid,
    required this.marker,
    required this.label,
  });

  final List<double> distances, elevations;
  final List<int> breaks;
  final double? markerM, touchM;
  final Color line, fill, grid, marker;
  final TextStyle label;

  /// Room for the height labels on the left and the distance below.
  static Rect plotRect(Size size) => Rect.fromLTRB(48, 14, size.width - 4, size.height - 14);

  @override
  void paint(Canvas canvas, Size size) {
    final plot = plotRect(size);
    final length = distances.last;
    final (:lo, :hi, :step) = profileAxis(elevations.reduce(min), elevations.reduce(max));
    double x(double m) => plot.left + (length == 0 ? 0 : m / length) * plot.width;
    double y(double e) => plot.bottom - (e - lo) / (hi - lo) * plot.height;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var e = (lo / step).ceil() * step; e <= hi + 0.1; e += step) {
      canvas.drawLine(Offset(plot.left, y(e)), Offset(plot.right, y(e)), gridPaint);
      _text(canvas, formatHeight(e), Offset(plot.left - 4, y(e)), align: Alignment.centerRight);
    }
    for (final (m, align) in [
      (0.0, Alignment.topLeft),
      (length / 2, Alignment.topCenter),
      (length, Alignment.topRight),
    ]) {
      _text(canvas, formatDistance(m), Offset(x(m), plot.bottom + 2), align: align);
    }

    // At most one sample per pixel column, keeping the highest and lowest.
    final path = Path()..moveTo(x(distances.first), y(elevations.first));
    var column = -1;
    double? colLo, colHi;
    for (var i = 1; i < distances.length; i++) {
      final c = x(distances[i]).floor();
      if (c != column && colLo != null) {
        path.lineTo(column + 0.5, y(colHi!));
        path.lineTo(column + 0.5, y(colLo));
        colLo = colHi = null;
      }
      column = c;
      colLo = colLo == null ? elevations[i] : min(colLo, elevations[i]);
      colHi = colHi == null ? elevations[i] : max(colHi, elevations[i]);
    }
    path.lineTo(x(distances.last), y(elevations.last));
    final area = Path.from(path)
      ..lineTo(x(distances.last), plot.bottom)
      ..lineTo(x(distances.first), plot.bottom)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    for (final b in breaks) {
      if (b <= 0 || b >= distances.length) continue;
      canvas.drawLine(Offset(x(distances[b]), plot.top), Offset(x(distances[b]), plot.bottom), gridPaint);
    }
    for (final (m, color) in [(markerM, marker), (touchM, line)]) {
      if (m == null) continue;
      final at = Offset(x(m), y(_eleAt(m)));
      canvas.drawLine(
        Offset(at.dx, plot.top),
        Offset(at.dx, plot.bottom),
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(at, 5, Paint()..color = Colors.white);
      canvas.drawCircle(at, 4, Paint()..color = color);
    }
  }

  double _eleAt(double m) => heightAt(distances, elevations, m);

  void _text(Canvas canvas, String s, Offset at, {required Alignment align}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: label),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = at.dx - tp.width * (align.x + 1) / 2;
    final dy = at.dy - tp.height * (align.y + 1) / 2;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_ProfilePainter old) =>
      old.markerM != markerM ||
      old.touchM != touchM ||
      !identical(old.distances, distances) ||
      !identical(old.elevations, elevations);
}
