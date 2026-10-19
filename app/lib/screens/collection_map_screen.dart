import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import '../api.dart';
import '../camera.dart';
import '../format.dart';
import '../map_credit.dart';
import '../map_style.dart';
import '../place_layer.dart';
import '../route_layers.dart';
import 'collections_screen.dart';
import 'wide.dart';

/// All routes and journeys of a collection on one map, each in its own
/// colour as on the website; below, the list. A tap on a line or an entry
/// opens it.
class CollectionMapScreen extends StatefulWidget {
  const CollectionMapScreen({super.key, required this.api, required this.collection, this.map});
  final Api api;
  final Collection collection;

  /// Replaces the map, in tests.
  final Widget? map;

  @override
  State<CollectionMapScreen> createState() => _CollectionMapScreenState();
}

class _CollectionMapScreenState extends State<CollectionMapScreen> {
  late final _places = PlaceLayer(widget.api, onTap: (p) => showPlace(context, p));
  MapController? _map;

  @override
  void dispose() {
    _places.dispose();
    super.dispose();
  }

  Color _color(int i) => Color(int.parse('FF${stageColors[i % stageColors.length].substring(1)}', radix: 16));

  void _onEvent(MapEvent e) {
    _places.onEvent(e);
    switch (e) {
      case MapEventMapCreated(:final mapController):
        _map = mapController;
      case MapEventClick(:final screenPoint):
        _tap(screenPoint);
      default:
    }
  }

  /// A finger is wider than a line; a hut on a line opens the hut.
  void _tap(Offset at) {
    final map = _map;
    if (map == null) return;
    final area = Rect.fromCircle(center: at, radius: 16);
    if (map.featuresInRect(area, layerIds: ['places']).isNotEmpty) return;
    final found = map.featuresInRect(area, layerIds: ['stages-line']);
    final i = (found.firstOrNull?.properties['stage'] as num?)?.toInt();
    final items = widget.collection.items;
    if (i != null && i < items.length) openCollectionItem(context, widget.api, widget.collection, items[i]);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.collection;
    // Each item's lines (a journey's stages) in the item's colour.
    final lines = [
      for (final (i, it) in c.items.indexed)
        for (final l in it.lines) (i, l),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(c.title)),
      body: MapSplit(
        height: 180,
        map: Stack(
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
                      onEvent: _onEvent,
                      onStyleLoaded: (style) async {
                        await _places.addTo(style);
                        await addStageLines(style, lines);
                      },
                    );
                  },
                ),
            Positioned(top: 12, left: 12, right: 64, child: MapCorner(places: _places)),
            const Positioned(top: 12, right: 12, child: PlaceLayerButton()),
          ],
        ),
        panel: ListView(
          key: const Key('collection-map-items'),
          children: [
            for (final (i, it) in c.items.indexed)
              ListTile(
                key: Key('collection-map-${it.id}'),
                dense: true,
                leading: CircleAvatar(radius: 8, backgroundColor: _color(i)),
                title: Text(it.title),
                subtitle: Text(
                  '${formatDistance(it.distanceM)} · ${formatHikingTime(it.durationS)} · '
                  '↑ ${formatHeight(it.ascentM)}',
                ),
                onTap: () => openCollectionItem(context, widget.api, c, it),
              ),
          ],
        ),
      ),
    );
  }
}
