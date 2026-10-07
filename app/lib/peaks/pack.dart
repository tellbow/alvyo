import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A named summit of the pack.
class Summit {
  const Summit(this.name, this.ele, this.lon, this.lat);
  final String name;
  final int ele;
  final double lon, lat;
}

/// The pack for recognising mountains (`GET /peaks/pack`, format in the
/// API's internal/peaks): a height grid of Switzerland and about 50 km
/// around it, and the named summits.
class PeakPack {
  PeakPack({
    required this.west,
    required this.north,
    required this.cellLon,
    required this.cellLat,
    required this.cols,
    required this.rows,
    required this.heights,
    required this.summits,
  });

  /// Reads a gzipped pack.
  factory PeakPack.decode(List<int> gzipped) {
    final bytes = Uint8List.fromList(gzip.decode(gzipped));
    final data = ByteData.sublistView(bytes);
    if (ascii.decode(bytes.sublist(0, 8), allowInvalid: true) != 'ALVYOPK1') {
      throw const FormatException('not a peaks pack');
    }
    var at = 12; // after the magic and the version
    double f64() => data.getFloat64((at += 8) - 8, Endian.little);
    int u32() => data.getUint32((at += 4) - 4, Endian.little);
    final west = f64(), north = f64(), cellLon = f64(), cellLat = f64();
    final cols = u32(), rows = u32();
    final heights = Int16List(cols * rows);
    for (var r = 0; r < rows; r++) {
      var h = 0;
      for (var c = 0; c < cols; c++) {
        h += data.getInt16(at, Endian.little);
        at += 2;
        heights[r * cols + c] = h;
      }
    }
    final summits = <Summit>[];
    for (var n = u32(); n > 0; n--) {
      final lon = data.getFloat32(at, Endian.little), lat = data.getFloat32(at + 4, Endian.little);
      final ele = data.getInt16(at + 8, Endian.little), size = data.getUint16(at + 10, Endian.little);
      at += 12;
      summits.add(Summit(utf8.decode(bytes.sublist(at, at + size)), ele, lon, lat));
      at += size;
    }
    return PeakPack(
      west: west,
      north: north,
      cellLon: cellLon,
      cellLat: cellLat,
      cols: cols,
      rows: rows,
      heights: heights,
      summits: summits,
    );
  }

  final double west, north, cellLon, cellLat;
  final int cols, rows;
  final Int16List heights;
  final List<Summit> summits;

  /// The height at a point, between the cells' centres; null outside.
  double? height(double lon, double lat) {
    final x = (lon - west) / cellLon - 0.5, y = (north - lat) / cellLat - 0.5;
    if (x < 0 || y < 0 || x > cols - 1 || y > rows - 1) return null;
    final c = x.floor().clamp(0, cols - 2), r = y.floor().clamp(0, rows - 2);
    final fx = x - c, fy = y - r;
    final i = r * cols + c;
    final top = heights[i] * (1 - fx) + heights[i + 1] * fx;
    final bottom = heights[i + cols] * (1 - fx) + heights[i + cols + 1] * fx;
    return top * (1 - fy) + bottom * fy;
  }
}
