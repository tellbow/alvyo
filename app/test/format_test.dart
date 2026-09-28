import 'package:flutter_test/flutter_test.dart';
import 'package:alvyo/format.dart';

void main() {
  test('numbers in the app’s language, the unit on the same line', () {
    expect(formatDistance(19349, 'de'), '19.3 km');
    expect(formatDistance(19349, 'fr'), '19,3 km');
    expect(formatDistance(19349, 'it'), '19.3 km');
    expect(formatDistance(152.4, 'fr'), '152 m');
    expect(formatHeight(1706.6), '1707 m');
    expect(formatDuration(9 * 3600 + 35 * 60), '9 h 35 min');
  });
}
