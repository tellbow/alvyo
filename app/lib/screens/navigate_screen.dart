import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre/maplibre.dart';

import '../api.dart';
import '../camera.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../map_style.dart';
import '../navigation/alerts.dart';
import '../navigation/gps.dart';
import '../navigation/recording.dart';
import '../navigation/tracker.dart';
import '../offline/packs.dart';
import '../route_layers.dart';

/// What was recorded, for the route screen to show.
class HikeSummary {
  const HikeSummary(this.distanceM, this.duration);
  final double distanceM;
  final Duration duration;
}

/// Hiking a route: the position on the (offline) map, how far it is still,
/// a warning when leaving the route, and a recording of the hike.
class NavigateScreen extends StatefulWidget {
  const NavigateScreen({
    super.key,
    required this.api,
    required this.route,
    this.pack,
    this.positions,
    this.recordings,
    this.alerts,
  });

  final Api api;
  final RouteDetail route;

  /// The saved offline map, if any.
  final SavedPack? pack;

  /// For tests: positions instead of the GPS.
  final Stream<Fix> Function()? positions;
  final Directory? recordings;
  final Alerts? alerts;

  @override
  State<NavigateScreen> createState() => _NavigateScreenState();
}

class _NavigateScreenState extends State<NavigateScreen> {
  late final RouteTracker _tracker = RouteTracker(widget.route.line, durationS: widget.route.totals.durationS);
  late final Alerts _alerts = widget.alerts ?? Alerts();
  Recording? _recording;
  StreamSubscription<Fix>? _sub;
  MapController? _map;
  StyleController? _style;
  Progress? _progress;
  Fix? _fix;
  bool _follow = true;
  bool _denied = false;

  /// While following the position; panning or zooming stops following.
  static const _followZoom = 15.0;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    widget.api
        .me()
        .then((m) {
          if (mounted) setState(() => _tracker.speedFactor = m.speedFactor);
        })
        .catchError((_) {}); // offline: the signposts' pace
    _start();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {})); // elapsed time
  }

  Future<void> _start() async {
    final root = widget.recordings ?? await Recording.defaultRoot();
    var rec = await Recording.active(root);
    if (rec != null && rec.routeId != widget.route.id) {
      await rec.finish(); // another route's hike: keep it, start this one
      rec = null;
    }
    rec ??= await Recording.start(root, routeId: widget.route.id, title: widget.route.title);
    // Resumed: continue where the hike was.
    for (final f in await rec.fixes()) {
      _progress = _tracker.update(f) ?? _progress;
    }
    if (widget.positions == null && !await locationAllowed()) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    if (!mounted) return;
    setState(() => _recording = rec);
    _sub = (widget.positions ?? gpsFixes)().listen(_onFix);
    unawaited(_alerts.init()); // asks for notifications without holding up the GPS
  }

  Future<void> _onFix(Fix fix) async {
    await _recording?.add(fix);
    final wasOff = _progress?.offRoute ?? false;
    final p = _tracker.update(fix);
    if (!mounted) return;
    setState(() {
      _fix = fix;
      _progress = p ?? _progress;
    });
    await _style?.updateGeoJsonSource(
      id: 'me',
      data: jsonEncode({
        'type': 'Point',
        'coordinates': [fix.lon, fix.lat],
      }),
    );
    if (_follow) {
      // A short glide rather than a jump to each position.
      await _map?.animateCamera(
        center: Geographic(lon: fix.lon, lat: fix.lat),
        zoom: _followZoom,
        nativeDuration: const Duration(milliseconds: 400),
      );
    }
    if (p == null || p.offRoute == wasOff || !mounted) return;
    final t = AppLocalizations.of(context);
    if (p.offRoute) {
      await HapticFeedback.vibrate();
      await _alerts.offRoute(t.navOffRouteTitle, t.navOffRoute(p.distanceToRouteM.round()));
    } else {
      await _alerts.clear();
    }
  }

  Future<void> _onStyle(StyleController style) async {
    _style = style;
    await addRouteLine(style, widget.route.line);
    final f = _fix;
    await style.addSource(
      GeoJsonSource(
        id: 'me',
        data: jsonEncode(
          f == null
              ? {'type': 'FeatureCollection', 'features': []}
              : {
                  'type': 'Point',
                  'coordinates': [f.lon, f.lat],
                },
        ),
      ),
    );
    await style.addLayer(
      const CircleStyleLayer(
        id: 'me-halo',
        sourceId: 'me',
        paint: {'circle-radius': 16, 'circle-color': '#2563eb', 'circle-opacity': 0.2},
      ),
    );
    await style.addLayer(
      const CircleStyleLayer(
        id: 'me-dot',
        sourceId: 'me',
        paint: {
          'circle-radius': 7,
          'circle-color': '#2563eb',
          'circle-stroke-color': '#ffffff',
          'circle-stroke-width': 2,
        },
      ),
    );
  }

  Future<void> _finish() async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(t.navFinishQuestion),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.navContinue)),
          FilledButton(
            key: const Key('nav-finish-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.navFinish),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _sub?.cancel();
    _sub = null;
    await _alerts.clear();
    final rec = _recording;
    HikeSummary? summary;
    if (rec != null) {
      final fixes = await rec.fixes();
      await rec.finish();
      summary = HikeSummary(
        trackLengthM(fixes),
        fixes.isEmpty ? Duration.zero : fixes.last.time.difference(rec.started),
      );
    }
    if (mounted) Navigator.of(context).pop(summary);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final r = widget.route;
    final p = _progress;
    final pack = widget.pack;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(r.title),
          actions: [TextButton(key: const Key('nav-finish'), onPressed: _finish, child: Text(t.navFinish))],
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, size) {
                      final view = fitLine(r.line, size.maxWidth, size.maxHeight);
                      return MapLibreMap(
                        options: MapOptions(
                          initStyle: pack != null ? offlineStyle(pack.files) : swisstopoStyle(widget.api.server),
                          initCenter: Geographic(lon: view.lon, lat: view.lat),
                          initZoom: view.zoom,
                        ),
                        onMapCreated: (c) => _map = c,
                        onStyleLoaded: _onStyle,
                        onEvent: (e) {
                          if (e is MapEventStartMoveCamera && e.reason == CameraChangeReason.apiGesture && _follow) {
                            setState(() => _follow = false);
                          }
                        },
                      );
                    },
                  ),
                  if (!_follow && _fix != null)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: FloatingActionButton.small(
                        key: const Key('nav-follow'),
                        tooltip: t.navFollow,
                        onPressed: () {
                          setState(() => _follow = true);
                          final f = _fix!;
                          _map?.animateCamera(
                            center: Geographic(lon: f.lon, lat: f.lat),
                            zoom: _followZoom,
                            nativeDuration: const Duration(milliseconds: 400),
                          );
                        },
                        child: const Icon(Icons.my_location),
                      ),
                    ),
                ],
              ),
            ),
            if (p != null && p.offRoute)
              _Banner(
                key: const Key('nav-off-route'),
                color: Theme.of(context).colorScheme.errorContainer,
                text: t.navOffRoute(p.distanceToRouteM.round()),
              )
            else if (p != null && p.arrived)
              _Banner(color: Theme.of(context).colorScheme.primaryContainer, text: t.navArrived),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: _denied
                    ? Text(t.navNoPermission)
                    : p == null
                    ? Text(t.navWaiting)
                    : Row(
                        key: const Key('nav-progress'),
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _Stat(t.navDone, formatDistance(p.doneM)),
                          _Stat(
                            t.navRemaining,
                            '${formatDistance(p.remainingM)} · ${formatDuration(p.remaining.inSeconds)}',
                          ),
                          if (_recording != null)
                            _Stat(
                              t.navElapsed,
                              formatDuration(DateTime.now().difference(_recording!.started).inSeconds),
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

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.labelMedium),
        Text(value, style: theme.titleMedium),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: color,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}
