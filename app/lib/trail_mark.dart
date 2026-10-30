import 'package:flutter/material.dart';

const _yellow = Color(0xFFFCD116);
const _ink = Color(0xFF1A1A1A);

/// The trail marking: the yellow diamond of a Wanderweg, white-red-white of
/// a Bergwanderweg, white-blue-white of an Alpinwanderweg; nothing off the
/// official network (feedback issue 71). Its name stands beside it, so
/// screen readers skip it.
class TrailMark extends StatelessWidget {
  const TrailMark(this.trail, {super.key});
  final String trail;

  @override
  Widget build(BuildContext context) {
    final CustomPainter? painter = switch (trail) {
      'Wanderweg' => _Diamond(),
      'Bergwanderweg' => _Band(const Color(0xFFE3242B)),
      'Alpinwanderweg' => _Band(const Color(0xFF2F6FDE)),
      _ => null,
    };
    if (painter == null) return const SizedBox.shrink();
    final mark = CustomPaint(
      key: Key('trail-mark-$trail'),
      size: painter is _Diamond ? const Size(12, 12) : const Size(16, 10),
      painter: painter,
    );
    return ExcludeSemantics(child: mark);
  }
}

class _Diamond extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Path()
      ..moveTo(s.width / 2, 1)
      ..lineTo(s.width - 1, s.height / 2)
      ..lineTo(s.width / 2, s.height - 1)
      ..lineTo(1, s.height / 2)
      ..close();
    c.drawPath(p, Paint()..color = _yellow);
    c.drawPath(
      p,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_Diamond old) => false;
}

class _Band extends CustomPainter {
  _Band(this.color);
  final Color color;

  @override
  void paint(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(r, Paint()..color = Colors.white);
    c.drawRect(Rect.fromLTWH(0, s.height / 3, s.width, s.height / 3), Paint()..color = color);
    c.drawRect(
      r,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_Band old) => old.color != color;
}
