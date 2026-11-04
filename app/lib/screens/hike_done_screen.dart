import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre/maplibre.dart';

import '../api.dart';
import '../camera.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../map_credit.dart';
import '../map_style.dart';
import '../motion.dart';
import '../route_layers.dart';
import 'canton_map.dart';
import 'navigate_screen.dart';

/// Shows [HikeDoneScreen] for a hike with a line, and returns when it is closed.
Future<void> showHikeDone(
  NavigatorState nav,
  Api api,
  HikeSummary summary,
  Future<void> uploaded, {
  Widget? map,
}) async {
  if (summary.line.length < 2) return;
  await nav.push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => HikeDoneScreen(api: api, summary: summary, uploaded: uploaded, map: map),
    ),
  );
}

/// The end of a hike: its line draws itself on the map and its numbers count
/// up, once; a touch skips that. Once uploaded, a canton hiked for the first
/// time fills in.
class HikeDoneScreen extends StatefulWidget {
  const HikeDoneScreen({super.key, required this.api, required this.summary, required this.uploaded, this.map});
  final Api api;
  final HikeSummary summary;

  /// Done when the hike reached the server, as far as it can.
  final Future<void> uploaded;

  /// Replaces the map, in tests.
  final Widget? map;

  @override
  State<HikeDoneScreen> createState() => _HikeDoneScreenState();
}

class _HikeDoneScreenState extends State<HikeDoneScreen> with SingleTickerProviderStateMixin {
  static const _draw = Duration(milliseconds: 1400);
  late final _count = AnimationController(vsync: this, duration: _draw);
  late final _eased = CurvedAnimation(parent: _count, curve: Curves.easeOutCubic);
  late final _tiles = WhenTilesIn(_go);
  StyleController? _style;
  var _started = false;
  Achievements? _achievements;
  List<String> _fresh = const [];

  @override
  void initState() {
    super.initState();
    _count.addStatusListener((s) {
      if (s == AnimationStatus.completed) HapticFeedback.lightImpact();
    });
    unawaited(_newCantons());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (lessMotion(context)) {
      _count.value = 1;
    } else if (widget.map != null) {
      _go();
    } else {
      _tiles.arm();
    }
  }

  /// The numbers and the line start together, once the map is there.
  void _go() {
    if (_count.isCompleted) return;
    _count.forward();
    if (_style case final style?) _drawLine(style);
  }

  void _drawLine(StyleController style) {
    unawaited(
      drawRouteLine(style, widget.summary.line, duration: _draw, stopped: () => !mounted || _count.isCompleted),
    );
  }

  Future<void> _newCantons() async {
    try {
      await widget.uploaded;
      final a = await widget.api.achievements();
      final fresh = await SeenCantons.instance.fresh(a.cantons);
      if (mounted && fresh.isNotEmpty) {
        setState(() {
          _achievements = a;
          _fresh = fresh;
        });
      }
    } on Object {
      // Offline: «Meine Wanderungen» shows it later.
    }
  }

  void _skip() {
    if (!_count.isCompleted) _count.value = 1;
  }

  @override
  void dispose() {
    _tiles.dispose();
    _eased.dispose();
    _count.dispose();
    super.dispose();
  }

  Widget _map() =>
      widget.map ??
      LayoutBuilder(
        builder: (context, size) {
          final line = widget.summary.line;
          final view = fitLine(line, size.maxWidth, size.maxHeight);
          return MapLibreMap(
            options: MapOptions(
              initStyle: swisstopoStyle(widget.api.server),
              initCenter: Geographic(lon: view.lon, lat: view.lat),
              initZoom: view.zoom,
            ),
            onEvent: _tiles.onEvent,
            onStyleLoaded: (style) async {
              final draw = !_count.isCompleted;
              await addRouteLine(style, draw ? const [] : line);
              _style = style;
              // Already going, without the map: the line catches up.
              if (draw && _count.isAnimating) _drawLine(style);
            },
          );
        },
      );

  Widget _stat(String label, String Function(double) value) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Semantics(
        label: '$label: ${value(1)}',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedBuilder(
                animation: _eased,
                builder: (context, _) => Text(
                  value(_eased.value),
                  style: text.headlineMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
              Text(label, style: text.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final s = widget.summary;
    return Listener(
      onPointerDown: (_) => _skip(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        key: const Key('hike-done'),
        appBar: AppBar(title: Text(t.hikeDoneTitle), automaticallyImplyLeading: false),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _map()),
                  const Positioned(left: 8, bottom: 8, right: 8, child: MapCredit()),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _stat(t.hikedDistance, (v) => formatDistance(s.distanceM * v)),
                        _stat(t.hikedTime, (v) => formatDuration((s.duration.inSeconds * v).round())),
                      ],
                    ),
                    if (_achievements case final a?) ...[
                      const SizedBox(height: 12),
                      CantonMap(walked: a.cantons, fresh: _fresh, height: 110),
                      Text(
                        t.hikedNewCanton(_fresh.join(', ')),
                        key: const Key('hike-done-canton'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('hike-done-close'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(t.hikeDoneClose),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
