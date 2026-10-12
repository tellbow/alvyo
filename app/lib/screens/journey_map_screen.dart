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
import '../precip.dart';
import 'route_screen.dart';

/// All stages of a journey on one map, in their colours, with the layer
/// menu; below, the stages, each opening as a route.
class JourneyMapScreen extends StatefulWidget {
  const JourneyMapScreen({super.key, required this.api, required this.journey, this.map});
  final Api api;
  final JourneyDetail journey;

  /// Replaces the map, in tests.
  final Widget? map;

  @override
  State<JourneyMapScreen> createState() => _JourneyMapScreenState();
}

class _JourneyMapScreenState extends State<JourneyMapScreen> {
  late final _places = PlaceLayer(widget.api, onTap: (p) => showPlace(context, p));

  @override
  void dispose() {
    _places.dispose();
    super.dispose();
  }

  Color _color(int i) => Color(int.parse('FF${stageColors[i % stageColors.length].substring(1)}', radix: 16));

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final j = widget.journey;
    final lines = j.stageLines;
    return Scaffold(
      appBar: AppBar(title: Text(j.title)),
      body: Column(
        children: [
          Expanded(
            child: Stack(
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
                          onStyleLoaded: (style) async {
                            await _places.addTo(style);
                            await addStageLines(style, lines);
                          },
                        );
                      },
                    ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 64,
                  child: MapCorner(precip: PrecipBar(controller: _places.precip)),
                ),
                const Positioned(top: 12, right: 12, child: PlaceLayerButton()),
              ],
            ),
          ),
          SizedBox(
            height: 180,
            child: ListView(
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
                        '↑ ${formatHeight(totals.ascentM)}',
                      ),
                      _ => Text(t.journeyNoRoute),
                    },
                    onTap: switch (s.routeId) {
                      final id? => () {
                        widget.api.shareTokenFor(id, widget.api.shareTokens[widget.journey.id]);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RouteScreen(
                              api: widget.api,
                              id: id,
                              title: s.title.isEmpty ? t.journeyStage(i + 1) : s.title,
                            ),
                          ),
                        );
                      },
                      _ => null,
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
