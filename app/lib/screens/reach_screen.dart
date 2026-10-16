import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import '../api.dart';
import '../camera.dart';
import '../l10n/app_localizations.dart';
import '../map_credit.dart';
import '../map_style.dart';
import '../navigation/gps.dart';
import '../place_layer.dart';
import '../place_search.dart';
import '../precip.dart';

import 'plan_sheet.dart';
import 'planner_screen.dart';
import 'wide.dart';

/// «Wie weit komme ich?»: from a point on the map, a place or where one is,
/// the areas reached on foot within 2, 4 and 8 hours at one's pace, as on
/// the website's «Reichweite».
class ReachScreen extends StatefulWidget {
  const ReachScreen({super.key, required this.api, @visibleForTesting this.map, this.embedded = false, this.onSaved});
  final Api api;

  /// A route planned from here was saved.
  final VoidCallback? onSaved;

  /// Inside Planen (requirement 69): without its app bar.
  final bool embedded;

  /// Instead of the map, in widget tests (MapLibre cannot render there).
  @visibleForTesting
  final Widget? map;

  @override
  State<ReachScreen> createState() => ReachScreenState();
}

/// The colours of the hours, as on the website.
const reachColors = {2: Color(0xff16a34a), 4: Color(0xffeab308), 8: Color(0xffdc2626)};

/// The fewest hours whose area holds [at] (inside an odd number of an
/// area's rings), or null outside all.
int? reachedWithin(List<ReachArea> areas, LonLat at) {
  int? best;
  for (final a in areas) {
    var inside = false;
    for (final ring in a.outline) {
      for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        final (xi, yi, xj, yj) = (ring[i][0], ring[i][1], ring[j][0], ring[j][1]);
        if ((yi > at.lat) != (yj > at.lat) && at.lon < (xj - xi) * (at.lat - yi) / (yj - yi) + xi) inside = !inside;
      }
    }
    if (inside && (best == null || a.hours < best)) best = a.hours;
  }
  return best;
}

String _hex(Color c) => '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';

class ReachScreenState extends State<ReachScreen> {
  late final _places = PlaceLayer(widget.api, onTap: (p) => showPlace(context, p));
  MapController? _map;
  StyleController? _style;
  String _profile = 'hike';

  /// Back at the start within the hours (requirement 69); one way unless
  /// chosen.
  bool _back = false;

  /// [found]: [name] is a place found by search, not «Punkt auf der Karte».
  ({LonLat at, String name, bool found})? _start;
  List<ReachArea> _areas = const [];
  bool _busy = false;
  String? _error;
  double _pace = 1;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    widget.api.me().then((me) {
      if (mounted) setState(() => _pace = me.speedFactor);
    }, onError: (Object _) {});
  }

  Future<void> _reach() async {
    final start = _start;
    if (start == null) return;
    final t = AppLocalizations.of(context);
    final mine = ++_asked;
    setState(() {
      _busy = true;
      _error = null;
    });
    List<ReachArea> areas = const [];
    String? error;
    try {
      areas = await widget.api.reach(start.at, profile: _profile, back: _back);
    } on ApiException catch (e) {
      error = switch (e.status) {
        422 => t.reachErrorNoPath,
        429 => t.reachErrorBusy,
        _ => t.reachErrorOther,
      };
    } on Object {
      error = t.reachErrorOther;
    }
    if (!mounted || mine != _asked) return;
    setState(() {
      _busy = false;
      _areas = areas;
      _error = error;
    });
    _draw();
    if (areas.isNotEmpty) _show(areas.last);
  }

  /// The map on [area] (the largest), in its part above the panel.
  void _show(ReachArea area) {
    final map = _map;
    final size = context.size;
    if (map == null || size == null || area.outline.isEmpty) return;
    // On a wide screen the panel is beside the map, not over it.
    final width = isWide(context) ? size.width - panelWidth : size.width;
    final above = size.height * (1 - PlanSheet.cover(context));
    final view = fitLine(area.outline.first, width, above, padding: 24, maxZoom: 13);
    // The centre moves down by half the panel, so the area sits above it.
    double y(double lat) {
      final s = sin(lat * pi / 180);
      return 0.5 - log((1 + s) / (1 - s)) / (4 * pi);
    }

    final cy = y(view.lat) + (size.height - above) / 2 / (512 * pow(2, view.zoom));
    final lat = 180 / pi * atan(_sinh(pi * (1 - 2 * cy)));
    map
        .animateCamera(
          center: Geographic(lon: view.lon, lat: lat),
          zoom: view.zoom,
        )
        .catchError((_) {});
  }

  static double _sinh(double x) => (exp(x) - exp(-x)) / 2;

  void _startAt(LonLat at, String name, {bool found = false}) {
    setState(() => _start = (at: at, name: name, found: found));
    _draw();
    _reach();
  }

  void _pick(FoundPlace p) {
    _startAt((lon: p.lon, lat: p.lat), p.name, found: true);
    _moveTo(p.lon, p.lat);
  }

  Future<void> _here() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final at = await locationAllowed() ? await knownPosition() : null;
    if (!mounted) return;
    if (at == null) {
      messenger.showSnackBar(SnackBar(content: Text(t.reachNoPosition)));
      return;
    }
    _startAt(at, t.reachHere);
    _moveTo(at.lon, at.lat);
  }

  void _moveTo(double lon, double lat) {
    final map = _map;
    if (map == null) return;
    map
        .animateCamera(
          center: Geographic(lon: lon, lat: lat),
          zoom: min(map.getCamera().zoom, 10),
        )
        .catchError((_) {});
  }

  /// A tap inside the areas: a route there from the start, with the same
  /// profile (and back with «Zurück zum Start»), or start from there.
  /// Called by tests too: their taps do not reach the native map.
  @visibleForTesting
  Future<void> tapped(LonLat at) async {
    final t = AppLocalizations.of(context);
    final start = _start;
    final hours = start == null ? null : reachedWithin(_areas, at);
    if (start == null || hours == null) return _startAt(at, t.reachMapPoint);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                _back ? t.reachWithinBack(hours) : t.reachWithin(hours),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              key: const Key('reach-plan-here'),
              leading: const Icon(Icons.route_outlined),
              title: Text(t.reachPlanHere),
              subtitle: _back ? Text(t.plannerRoundTrip) : null,
              onTap: () => Navigator.pop(context, 'plan'),
            ),
            ListTile(
              key: const Key('reach-start-here'),
              leading: const Icon(Icons.radar),
              title: Text(t.reachStartHere),
              onTap: () => Navigator.pop(context, 'start'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'start') _startAt(at, t.reachMapPoint);
    if (choice != 'plan') return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlannerScreen(
          api: widget.api,
          plan: (from: start.at, name: start.found ? start.name : null, to: at, profile: _profile, roundTrip: _back),
          onSaved: widget.onSaved,
          map: widget.map,
        ),
      ),
    );
  }

  LonLat? _near() {
    final c = _map?.getCamera().center;
    return c == null ? null : (lon: c.lon, lat: c.lat);
  }

  /// One source per hour: the iOS map takes them as they are.
  String _areaJson(int hours) => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final a in _areas)
        if (a.hours == hours)
          {
            'type': 'Feature',
            'geometry': {'type': 'Polygon', 'coordinates': a.outline},
            'properties': <String, Object>{},
          },
    ],
  });

  String _startJson() => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      if (_start case final s?)
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [s.at.lon, s.at.lat],
          },
          'properties': <String, Object>{},
        },
    ],
  });

  void _draw() {
    final style = _style;
    if (style == null) return;
    for (final h in reachColors.keys) {
      style.updateGeoJsonSource(id: 'reach-$h', data: _areaJson(h)).catchError((_) {});
    }
    style.updateGeoJsonSource(id: 'reach-start', data: _startJson()).catchError((_) {});
  }

  @override
  void dispose() {
    _places.dispose();
    super.dispose();
  }

  Future<void> _addLayers(StyleController style) async {
    await _places.addTo(style);
    // The largest underneath; a white edge under each outline, as the
    // trails are yellow and red too.
    for (final h in [8, 4, 2]) {
      final color = _hex(reachColors[h]!);
      await style.addSource(GeoJsonSource(id: 'reach-$h', data: _areaJson(h)));
      await style.addLayer(
        FillStyleLayer(id: 'reach-$h-fill', sourceId: 'reach-$h', paint: {'fill-color': color, 'fill-opacity': 0.35}),
      );
      await style.addLayer(
        LineStyleLayer(id: 'reach-$h-edge', sourceId: 'reach-$h', paint: {'line-color': '#ffffff', 'line-width': 5}),
      );
      await style.addLayer(
        LineStyleLayer(id: 'reach-$h-line', sourceId: 'reach-$h', paint: {'line-color': color, 'line-width': 2.5}),
      );
    }
    await style.addSource(GeoJsonSource(id: 'reach-start', data: _startJson()));
    await style.addLayer(
      const CircleStyleLayer(
        id: 'reach-start',
        sourceId: 'reach-start',
        paint: {
          'circle-radius': 7,
          'circle-color': '#1c1917',
          'circle-stroke-color': '#ffffff',
          'circle-stroke-width': 2,
        },
      ),
    );
    _style = style;
  }

  Widget _mapLibre() => MapLibreMap(
    options: MapOptions(
      initStyle: swisstopoStyle(widget.api.server),
      initCenter: const Geographic(lon: 8.23, lat: 46.8),
      initZoom: 7,
    ),
    onEvent: (e) {
      _places.onEvent(e);
      switch (e) {
        case MapEventMapCreated(:final mapController):
          _map = mapController;
        case MapEventClick(:final point, :final screenPoint) when _style != null:
          // A tap on a hut opens its sheet instead.
          final hut = _map?.featuresInRect(Rect.fromCircle(center: screenPoint, radius: 16), layerIds: ['places']);
          if (hut == null || hut.isEmpty) tapped((lon: point.lon, lat: point.lat));
        default:
      }
    },
    onStyleLoaded: _addLayers,
  );

  late final Widget _mapView = widget.map ?? _mapLibre();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: Text(t.reachTitle)),
      body: PlanSheet(
        map: Stack(
          children: [
            Positioned.fill(child: _mapView),
            Positioned(
              top: 12,
              left: 12,
              right: 64,
              child: MapCorner(precip: PrecipBar(controller: _places.precip)),
            ),
            const Positioned(top: 12, right: 12, child: PlaceLayerButton()),
            if (_busy)
              Positioned(
                // Below the rain's bar.
                top: 64,
                left: 12,
                right: 12,
                child: Center(
                  child: Material(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text(t.reachBusy, style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                ),
              ),
          ],
        ),
        panelKey: const Key('reach-panel'),
        children: [
          Text(t.reachIntro, style: muted),
          const SizedBox(height: 12),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: PlaceSearch(api: widget.api, onPick: _pick, near: _near, label: t.reachSearch),
              ),
              IconButton.filledTonal(
                key: const Key('reach-here'),
                tooltip: t.reachHere,
                icon: const Icon(Icons.my_location),
                onPressed: _here,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            key: const Key('reach-profile'),
            segments: [
              ButtonSegment(value: 'hike', label: Text(t.plannerProfileHike)),
              ButtonSegment(value: 'alpine', label: Text(t.plannerProfileAlpine)),
            ],
            selected: {_profile},
            onSelectionChanged: (s) {
              setState(() => _profile = s.first);
              _reach();
            },
          ),
          CheckboxListTile(
            key: const Key('reach-back'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(t.plannerReturn),
            subtitle: Text(t.reachBackHint),
            value: _back,
            onChanged: (v) {
              setState(() => _back = v ?? false);
              _reach();
            },
          ),
          if (_start case final s?) ...[
            const SizedBox(height: 12),
            Text(t.reachStart(s.name), key: const Key('reach-start'), style: theme.textTheme.titleSmall),
          ],
          if (_error case final e?) ...[
            const SizedBox(height: 8),
            Text(
              e,
              key: const Key('reach-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ] else if (_areas.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final a in _areas)
              Padding(
                key: Key('reach-legend-${a.hours}'),
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  spacing: 8,
                  children: [
                    Icon(Icons.square_rounded, size: 14, color: reachColors[a.hours]),
                    Expanded(child: Text(_back ? t.reachWithinBack(a.hours) : t.reachWithin(a.hours))),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(t.reachPlanHint, key: const Key('reach-plan-hint')),
            const SizedBox(height: 8),
            Text(t.reachNote, style: muted),
            if (_pace != 1) Text(t.reachPace(_pace.toString()), style: muted),
          ],
        ],
      ),
    );
  }
}
