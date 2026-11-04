import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../l10n/app_localizations.dart';
import '../motion.dart';

/// The cantons the user has already seen on this phone, for telling which
/// are new. The first look only notes them: a new canton is one hiked later.
class SeenCantons {
  SeenCantons({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static final instance = SeenCantons();
  static const key = 'cantons-seen';

  final FlutterSecureStorage _storage;

  /// Those of [now] not seen before, which count as seen from here on.
  Future<List<String>> fresh(List<String> now) async {
    try {
      final old = await _storage.read(key: key);
      final seen = old == null ? <String>{} : old.split(',').toSet();
      await _storage.write(key: key, value: {...seen, ...now}.join(','));
      return old == null
          ? const []
          : [
              for (final c in now)
                if (!seen.contains(c)) c,
            ];
    } on Object {
      return const []; // no Keychain: nothing to celebrate, nothing lost
    }
  }
}

/// Each canton's rings of lon, lat points, the largest first: one inside
/// another (Appenzell Innerrhoden in Ausserrhoden) is painted over it. From
/// swissBOUNDARIES3D, simplified to about 900 m for this small map.
Future<List<(String, List<List<Offset>>)>> _load() async {
  final json = jsonDecode(await rootBundle.loadString('assets/cantons.json')) as Map<String, dynamic>;
  final shapes = [
    for (final e in json.entries)
      (
        e.key,
        [
          for (final ring in e.value as List)
            [for (final p in ring as List) Offset(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble())],
        ],
      ),
  ];
  double area(List<List<Offset>> rings) {
    final all = rings.expand((r) => r);
    final w = all.map((p) => p.dx).reduce(max) - all.map((p) => p.dx).reduce(min);
    final h = all.map((p) => p.dy).reduce(max) - all.map((p) => p.dy).reduce(min);
    return w * h;
  }

  return shapes..sort((a, b) => area(b.$2).compareTo(area(a.$2)));
}

/// Switzerland with the cantons walked in filled in; those in [fresh] fill
/// in once, in front of the user.
class CantonMap extends StatefulWidget {
  const CantonMap({super.key, required this.walked, this.fresh = const [], this.height = 150});
  final List<String> walked, fresh;
  final double height;

  @override
  State<CantonMap> createState() => _CantonMapState();
}

class _CantonMapState extends State<CantonMap> with SingleTickerProviderStateMixin {
  late final _shapes = _load();
  late final _fill = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final _eased = CurvedAnimation(parent: _fill, curve: Curves.easeOutCubic);
  var _started = false;

  @override
  void didUpdateWidget(CantonMap old) {
    super.didUpdateWidget(old);
    if (old.fresh.isEmpty && widget.fresh.isNotEmpty) _start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.fresh.isNotEmpty) _start();
  }

  void _start() {
    if (_started) return;
    _started = true;
    if (lessMotion(context)) {
      _fill.value = 1;
    } else {
      _fill.forward();
    }
    HapticFeedback.lightImpact();
  }

  @override
  void dispose() {
    _eased.dispose();
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      image: true,
      label: '${t.hikedCantons}: ${t.hikedOf(widget.walked.length, 26)}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              height: widget.height,
              width: double.infinity,
              child: FutureBuilder(
                future: _shapes,
                builder: (context, snap) => CustomPaint(
                  key: const Key('canton-map'),
                  painter: snap.data == null
                      ? null
                      : _CantonPainter(
                          snap.data!,
                          walked: widget.walked.toSet(),
                          fresh: widget.fresh.toSet(),
                          fill: _eased,
                          on: colors.primary,
                          off: colors.surfaceContainerHighest,
                          border: colors.surface,
                        ),
                ),
              ),
            ),
            // swissBOUNDARIES3D asks for its source.
            Text('© swisstopo', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _CantonPainter extends CustomPainter {
  _CantonPainter(
    this.shapes, {
    required this.walked,
    required this.fresh,
    required this.fill,
    required this.on,
    required this.off,
    required this.border,
  }) : super(repaint: fill);
  final List<(String, List<List<Offset>>)> shapes;
  final Set<String> walked, fresh;
  final Animation<double> fill;
  final Color on, off, border;

  // Longitude and latitude to a plane, at Switzerland's latitude.
  static final _xScale = cos(46.8 * pi / 180);

  @override
  void paint(Canvas canvas, Size size) {
    final all = shapes.expand((s) => s.$2).expand((r) => r);
    final west = all.map((p) => p.dx).reduce(min), east = all.map((p) => p.dx).reduce(max);
    final south = all.map((p) => p.dy).reduce(min), north = all.map((p) => p.dy).reduce(max);
    final scale = min(size.width / ((east - west) * _xScale), size.height / (north - south));
    final left = (size.width - (east - west) * _xScale * scale) / 2;
    final top = (size.height - (north - south) * scale) / 2;
    Offset at(Offset p) => Offset(left + (p.dx - west) * _xScale * scale, top + (north - p.dy) * scale);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75
      ..color = border;
    for (final (code, rings) in shapes) {
      final path = Path();
      for (final ring in rings) {
        path.addPolygon([for (final p in ring) at(p)], true);
      }
      final color = !walked.contains(code)
          ? off
          : fresh.contains(code)
          ? Color.lerp(off, on, fill.value)!
          : on;
      canvas
        ..drawPath(path, Paint()..color = color)
        ..drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(_CantonPainter old) =>
      old.shapes != shapes || old.walked != walked || old.fresh != fresh || old.on != on;
}
