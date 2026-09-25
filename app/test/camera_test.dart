import 'package:flutter_test/flutter_test.dart';
import 'package:alvyo/camera.dart';

void main() {
  test('fits a line into the view', () {
    // About 20 km east–west at 47° N: at zoom z the world is 512·2^z px.
    final c = fitLine(
      [
        [9.3, 47.0],
        [9.56, 47.0],
      ],
      400,
      600,
      padding: 0,
    );
    expect(c.lon, closeTo(9.43, 1e-9));
    expect(c.lat, closeTo(47.0, 1e-6));
    // 0.26° of 360° must fill 400 px: 400 / (0.26/360 · 512) = 1082 → zoom log2(1082) ≈ 10.08
    expect(c.zoom, closeTo(10.08, 0.01));
  });

  test('a single point does not zoom in past the limit', () {
    expect(
      fitLine(
        [
          [8.0, 46.5],
        ],
        400,
        600,
      ).zoom,
      16,
    );
  });
}
