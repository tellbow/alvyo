import 'dart:convert';

/// Switzerland and Liechtenstein with a margin; no tiles outside.
const chBounds = [5.7, 45.6, 10.8, 48.0];

const _layers = [
  {'id': 'landeskarte', 'type': 'raster', 'source': 'landeskarte'},
  {'id': 'wanderwege', 'type': 'raster', 'source': 'wanderwege'},
];

/// The swisstopo national map with the hiking trail overlay, through the
/// Alvyo tile cache of [server].
String swisstopoStyle(String server) {
  Map<String, Object> raster(String layer, String ext, int maxzoom) => {
    'type': 'raster',
    'tiles': ['$server/tiles/wmts/$layer/{z}/{x}/{y}.$ext'],
    'tileSize': 256,
    'maxzoom': maxzoom,
    'bounds': chBounds,
    'attribution': '© swisstopo',
  };
  return jsonEncode({
    'version': 8,
    'sources': {
      'landeskarte': raster('ch.swisstopo.pixelkarte-farbe', 'jpeg', 19),
      'wanderwege': raster('ch.swisstopo.swisstlm3d-wanderwege', 'png', 18),
    },
    'layers': _layers,
  });
}

/// A saved offline map: [files] are its PMTiles files by layer.
String offlineStyle(Map<String, String> files) => jsonEncode({
  'version': 8,
  'sources': {
    for (final e in files.entries) e.key: {'type': 'raster', 'url': 'pmtiles://${Uri.file(e.value)}', 'tileSize': 256},
  },
  'layers': _layers,
});
