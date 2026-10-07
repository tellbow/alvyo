import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:alvyo/peaks/pack.dart';
import 'package:alvyo/peaks/projection.dart';
import 'package:alvyo/peaks/view.dart';

import 'peaks_fixture.dart';

void main() {
  test('the pack: heights between the cells, the summits', () {
    final p = PeakPack.decode(
      peakPackBytes(10, 10, (lon, lat) => ((lon - 7) * 10000).round(), [const Summit('Säntis', 2502, 7.01, 47.19)]),
    );
    expect(p.cols, 10);
    expect(p.height(7.003, 47.19), closeTo(30, 0.01)); // between cells of 10 and 50 m … linear
    expect(p.height(6.9, 47.19), isNull);
    expect(p.summits.single.name, 'Säntis');
    expect(p.summits.single.ele, 2502);
  });

  test('the earth bends away: at 100 km the same height lies 0.39° lower', () {
    expect(elevationAngle(1000, 100000, 1000), closeTo(-0.39, 0.01));
    expect(elevationAngle(1000 + 1745, 100000, 1000), closeTo(0.61, 0.02));
  });

  test('summits behind a ridge are hidden, those before it and on it are named', () {
    // 500 m everywhere, a ridge of 3000 m along 47.0°N.
    final p = PeakPack.decode(
      peakPackBytes(500, 500, (lon, lat) => (lat - 47.0).abs() < 0.003 ? 3000 : 500, const [
        Summit('Behind', 2500, 7.5, 47.15),
        Summit('Before', 1500, 7.5, 46.9),
        Summit('Ridge', 3600, 7.6, 47.0), // 600 m above the ridge's flat top
      ]),
    );
    final v = computeView(p, 7.5, 46.95);
    expect(v.eye, closeTo(502, 0.01));
    expect(v.summits.map((s) => s.summit.name), ['Ridge', 'Before']);
    final ridge = v.summits.first;
    expect(ridge.azimuth, inInclusiveRange(40, 70)); // north-east
    // To the north, the skyline is the ridge's near edge, 5.23 km away.
    expect(v.skyline[0], closeTo(elevationAngle(3000, 5230, 502), 0.3));
  });

  group('projection', () {
    // Upright in portrait, the back camera to the north: the screen's right
    // is east (world −y), its top up (z), the user to the south (−x); the
    // rows are these axes.
    const north = CameraPose([0, -1, 0, 0, 0, 1, -1, 0, 0], fov: 60);
    const size = Size(400, 800);

    test('the view looks north and level', () {
      expect(north.centre.azimuth, closeTo(0, 1e-9));
      expect(north.centre.elevation, closeTo(0, 1e-9));
      expect(north.project(0, 0, size), const Offset(200, 400));
    });

    test('east to the right, up to the top, behind nowhere', () {
      final east = north.project(10, 0, size)!, up = north.project(0, 5, size)!;
      expect(east.dx, greaterThan(200));
      expect(east.dy, closeTo(400, 1e-6));
      expect(up.dy, lessThan(400));
      expect(north.project(180, 0, size), isNull);
    });

    test('the picture fills the screen: its long side over the height', () {
      // 30° (half the field) to the side of a 60° picture whose 4:3 long
      // side spans max(800, 400·4/3) = 800 px: 400 px from the centre.
      expect(north.project(0, 30, size)!.dy, closeTo(0, 1e-6));
    });
  });
}
