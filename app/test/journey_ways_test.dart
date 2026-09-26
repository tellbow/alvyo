import 'package:flutter_test/flutter_test.dart';
import 'package:alvyo/journey_ways.dart';

// Thun → Zermatt: over the Lötschenpass, or over the Gemmi; both sleep in
// Gampel on the third night. A third way meets neither.
const _ways = [
  ['Kandersteg', 'Gfellalp', 'Gampel', 'Kalpetran', null],
  ['Kandersteg', 'Gemmi', 'Gampel', 'St. Niklaus', null],
  ['Adelboden', 'Sierre', 'Gruben', null],
];

void main() {
  test('knows the ways that sleep at the same place', () {
    final picked = whole(_ways, 0);
    expect(switches(_ways, picked, 0), [(way: 1, stage: 0)]);
    expect(switches(_ways, picked, 1), isEmpty);
    expect(switches(_ways, picked, 2), [(way: 1, stage: 2)]);
    // The last day ends at the destination: nothing to change to.
    expect(switches(_ways, picked, 4), isEmpty);
  });

  test('goes on along another way', () {
    // Over the Lötschenpass to Gampel, then as the Gemmi way goes on.
    final picked = switchTo(_ways, whole(_ways, 0), 2, (way: 1, stage: 2));
    expect(stagesOf(_ways, picked), ['Kandersteg', 'Gfellalp', 'Gampel', 'St. Niklaus', null]);
    expect(single(_ways, picked), isNull);
    // And back along the first way from Kandersteg: all its days again.
    expect(single(_ways, switchTo(_ways, picked, 0, (way: 0, stage: 0))), 0);
  });

  test('changes at a night the ways reach on different days', () {
    const ways = [
      ['A', 'B', null],
      ['B', 'C', 'D', null],
    ];
    final picked = switchTo(ways, whole(ways, 0), 1, (way: 1, stage: 0));
    expect(stagesOf(ways, picked), ['A', 'B', 'C', 'D', null]);
  });

  test('a whole way is that way', () {
    expect(single(_ways, whole(_ways, 2)), 2);
    expect(single(_ways, const []), isNull);
  });
}
