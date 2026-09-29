import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:alvyo/poi_icons.dart';

void main() {
  test('the icons along the way are the website\'s', () {
    final web = jsonDecode(File('../web/src/lib/map/poi-icons.json').readAsStringSync()) as Map<String, dynamic>;
    expect(poiIcons.keys, web.keys);
    expect(poiKinds, web.keys);
    for (final MapEntry(:key, :value) in web.entries) {
      final icon = poiIcons[key]!;
      expect('#${icon.color.toRadixString(16).substring(2)}', value['color'], reason: key);
      expect(icon.evenOdd, value['evenodd'], reason: key);
      expect(icon.path, value['path'], reason: key);
    }
  });

  test('every icon path can be drawn', () {
    for (final icon in poiIcons.values) {
      final b = iconPath(icon.path).getBounds();
      expect(b.left, greaterThanOrEqualTo(0));
      expect(b.right, lessThanOrEqualTo(24));
      expect(b.width, greaterThan(8));
    }
  });
}
