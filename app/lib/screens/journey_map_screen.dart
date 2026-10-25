import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import '../api.dart';
import '../camera.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../map_credit.dart';
import '../map_style.dart';
import '../place_layer.dart';
import '../route_layers.dart';
import 'route_screen.dart';
import 'wide.dart';

/// All stages of a journey on one map, in their colours, with the layer
/// menu; below, the stages, each opening as a route.
class JourneyMapScreen extends StatelessWidget {
  const JourneyMapScreen({super.key, required this.api, required this.journey, this.map});
  final Api api;
  final JourneyDetail journey;

  /// Replaces the map, in tests.
  final Widget? map;

  Color _color(int i) => Color(int.parse('FF${stageColors[i % stageColors.length].substring(1)}', radix: 16));

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final j = journey;
    return Scaffold(
      appBar: AppBar(title: Text(j.title)),
      body: MapSplit(
        height: 180,
        map: JourneyMap(api: api, journey: j, map: map),
        panel: ListView(
          key: const Key('journey-map-stages'),
          children: [
            for (final (i, s) in j.stages.indexed)
              ListTile(
                dense: true,
                leading: CircleAvatar(radius: 8, backgroundColor: _color(i)),
                title: Text(s.title.isEmpty ? t.journeyStage(i + 1) : s.title),
                subtitle: switch (s.totals) {
                  final totals? => Text(
                    '${formatDistance(totals.distanceM)} · ${formatHikingTime(totals.durationS)} · '
                    '↑ ${formatHeight(totals.ascentM)}',
                  ),
                  _ => Text(t.journeyNoRoute),
                },
                onTap: switch (s.routeId) {
                  final id? => () {
                    api.shareTokenFor(id, api.shareTokens[j.id]);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            RouteScreen(api: api, id: id, title: s.title.isEmpty ? t.journeyStage(i + 1) : s.title),
                      ),
                    );
                  },
                  _ => null,
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// A journey's stages on the map, in their colours, with the layer menu;
/// also beside a journey on a wide screen.
class JourneyMap extends StatefulWidget {
  const JourneyMap({super.key, required this.api, required this.journey, this.map, this.picked, this.profilePoint});
  final Api api;
  final JourneyDetail journey;

  /// A part of a stage picked in a list (lines of [lon, lat]), shown when
  /// it changes.
  final ValueListenable<List<List<List<double>>>>? picked;

  /// The place under the finger on the elevation profile.
  final ValueListenable<Geographic?>? profilePoint;

  /// Replaces the map, in tests.
  final Widget? map;

  @override
  State<JourneyMap> createState() => _JourneyMapState();
}

class _JourneyMapState extends State<JourneyMap> {
  late final _places = PlaceLayer(widget.api, onTap: (p) => showPlace(context, p));
  MapController? _map;
  StyleController? _style;

  @override
  void initState() {
    super.initState();
    widget.picked?.addListener(_show);
    widget.profilePoint?.addListener(_showProfilePoint);
  }

  @override
  void dispose() {
    widget.picked?.removeListener(_show);
    widget.profilePoint?.removeListener(_showProfilePoint);
    _places.dispose();
    super.dispose();
  }

  void _show() {
    if ((_map, _style, widget.picked?.value) case (final map?, final style?, final parts?)) {
      showParts(map, style, parts).catchError((_) {});
    }
  }

  void _showProfilePoint() {
    if (_style case final style?) showProfilePoint(style, widget.profilePoint?.value).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.journey.stageLines;
    return Stack(
      children: [
        widget.map ??
            LayoutBuilder(
              builder: (context, size) {
                final view = fitLine([for (final (_, l) in lines) ...l], size.maxWidth, size.maxHeight);
                return MapLibreMap(
                  options: MapOptions(
                    initStyle: swisstopoStyle(widget.api.server),
                    initCenter: Geographic(lon: view.lon, lat: view.lat),
                    initZoom: view.zoom,
                  ),
                  onEvent: _places.onEvent,
                  onMapCreated: (c) => _map = c,
                  onStyleLoaded: (style) async {
                    _style = style;
                    await _places.addTo(style);
                    await addStageLines(style, lines);
                    await addHighlight(style);
                    await addProfilePoint(style);
                  },
                );
              },
            ),
        Positioned(top: 12, left: 12, right: 64, child: MapCorner(places: _places)),
        const Positioned(top: 12, right: 12, child: PlaceLayerButton()),
      ],
    );
  }
}
