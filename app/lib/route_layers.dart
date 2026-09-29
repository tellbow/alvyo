import 'dart:convert';

import 'package:maplibre/maplibre.dart';

/// The colours of a journey's stages, one after the other, as on the
/// website (neighbours differ also for red-green colour blindness).
const stageColors = ['#a21caf', '#4d7c0f', '#2563eb', '#c2410c', '#0f766e', '#be123c'];

/// A journey's stages (each a list of lon, lat points) in their colours,
/// with a white casing; [stages] maps each line to its stage (from 0).
Future<void> addStageLines(StyleController style, List<(int, List<List<double>>)> stages) async {
  await style.addSource(
    GeoJsonSource(
      id: 'stages',
      data: jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          for (final (i, line) in stages)
            if (line.length >= 2)
              {
                'type': 'Feature',
                'properties': {'color': stageColors[i % stageColors.length], 'stage': i},
                'geometry': {
                  'type': 'LineString',
                  'coordinates': [
                    for (final c in line) [c[0], c[1]],
                  ],
                },
              },
        ],
      }),
    ),
  );
  await style.addLayer(
    const LineStyleLayer(
      id: 'stages-casing',
      sourceId: 'stages',
      paint: {'line-color': '#ffffff', 'line-width': 7},
      layout: {'line-cap': 'round', 'line-join': 'round'},
    ),
  );
  await style.addLayer(
    const LineStyleLayer(
      id: 'stages-line',
      sourceId: 'stages',
      paint: {
        'line-color': ['get', 'color'],
        'line-width': 4,
      },
      layout: {'line-cap': 'round', 'line-join': 'round'},
    ),
  );
}

/// Draws a route line (lon, lat[, ele] points) on the map, like the website.
Future<void> addRouteLine(StyleController style, List<List<double>> line) async {
  await style.addSource(GeoJsonSource(id: 'route', data: lineJson(line)));
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

/// The data of the line drawn by [addRouteLine]; nothing below two points
/// (a track just started).
String lineJson(List<List<double>> line) => jsonEncode(
  line.length < 2
      ? _nothing
      : {
          'type': 'Feature',
          'properties': {},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final c in line) [c[0], c[1]],
            ],
          },
        },
);

const _nothing = {'type': 'FeatureCollection', 'features': <Object>[]};

/// The data of the dot drawn by [addPositionDot]: the position, if known.
String positionJson(double? lon, double? lat) => jsonEncode(
  lon == null || lat == null
      ? _nothing
      : {
          'type': 'Point',
          'coordinates': [lon, lat],
        },
);

/// The phone's position as a blue dot; moved with
/// `updateGeoJsonSource(id: 'me', data: positionJson(…))`.
Future<void> addPositionDot(StyleController style, double? lon, double? lat) async {
  await style.addSource(GeoJsonSource(id: 'me', data: positionJson(lon, lat)));
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
