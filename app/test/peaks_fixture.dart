import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alvyo/peaks/pack.dart';

/// A pack as the API writes it, of [rows]×[cols] cells from 7°E, 47.2°N.
List<int> peakPackBytes(int cols, int rows, int Function(double lon, double lat) height, List<Summit> summits) {
  const west = 7.0, north = 47.2, cellLon = 0.002, cellLat = 0.00128;
  final b = BytesBuilder()..add(ascii.encode('ALVYOPK1'));
  final head = ByteData(4 + 4 * 8 + 8)
    ..setUint32(0, 1, Endian.little)
    ..setFloat64(4, west, Endian.little)
    ..setFloat64(12, north, Endian.little)
    ..setFloat64(20, cellLon, Endian.little)
    ..setFloat64(28, cellLat, Endian.little)
    ..setUint32(36, cols, Endian.little)
    ..setUint32(40, rows, Endian.little);
  b.add(head.buffer.asUint8List());
  final grid = ByteData(rows * cols * 2);
  for (var r = 0; r < rows; r++) {
    var prev = 0;
    for (var c = 0; c < cols; c++) {
      final h = height(west + (c + 0.5) * cellLon, north - (r + 0.5) * cellLat);
      grid.setInt16((r * cols + c) * 2, h - prev, Endian.little);
      prev = h;
    }
  }
  b.add(grid.buffer.asUint8List());
  b.add((ByteData(4)..setUint32(0, summits.length, Endian.little)).buffer.asUint8List());
  for (final s in summits) {
    final name = utf8.encode(s.name);
    b.add(
      (ByteData(12)
            ..setFloat32(0, s.lon, Endian.little)
            ..setFloat32(4, s.lat, Endian.little)
            ..setInt16(8, s.ele, Endian.little)
            ..setUint16(10, name.length, Endian.little))
          .buffer
          .asUint8List(),
    );
    b.add(name);
  }
  return gzip.encode(b.toBytes());
}
