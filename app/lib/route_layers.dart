import 'dart:convert';

import 'package:maplibre/maplibre.dart';

/// Draws a route line (lon, lat[, ele] points) on the map, like the website.
Future<void> addRouteLine(StyleController style, List<List<double>> line) async {
  final geojson = jsonEncode({
    'type': 'Feature',
    'properties': {},
    'geometry': {
      'type': 'LineString',
      'coordinates': [
        for (final c in line) [c[0], c[1]],
      ],
    },
  });
  await style.addSource(GeoJsonSource(id: 'route', data: geojson));
  await style.addLayer(
    const LineStyleLayer(
      id: 'route-casing',
      sourceId: 'route',
      paint: {'line-color': '#ffffff', 'line-width': 7},
      layout: {'line-cap': 'round', 'line-join': 'round'},
    ),
  );
  await style.addLayer(
    const LineStyleLayer(
      id: 'route-line',
      sourceId: 'route',
      paint: {'line-color': '#7e22ce', 'line-width': 4},
      layout: {'line-cap': 'round', 'line-join': 'round'},
    ),
  );
}
