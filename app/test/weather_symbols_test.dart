import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:alvyo/weather_symbols.dart';

void main() {
  test('the weather icons and symbols are the website\'s', () {
    final web = jsonDecode(File('../web/src/lib/weather/symbols.json').readAsStringSync()) as Map<String, dynamic>;
    final icons = web['icons'] as Map<String, dynamic>;
    expect(weatherIcons.keys, icons.keys);
    for (final MapEntry(:key, :value) in icons.entries) {
      final layers = value as List;
      expect(weatherIcons[key]!.length, layers.length, reason: key);
      for (final (i, l) in layers.indexed) {
        expect('#${weatherIcons[key]![i].color.toRadixString(16).substring(2)}', l['color'], reason: key);
        expect(weatherIcons[key]![i].path, l['path'], reason: key);
      }
    }
    final symbols = web['symbols'] as Map<String, dynamic>;
    expect(weatherSymbols.length, symbols.length);
    for (final MapEntry(:key, :value) in symbols.entries) {
      final s = weatherSymbols[int.parse(key)]!;
      expect([s.icon, s.de, s.fr, s.it, s.en], [value['icon'], value['de'], value['fr'], value['it'], value['en']]);
    }
  });

  test('symbols by number and language, the night\'s as the day\'s', () {
    expect(weatherSymbol(1, 'de'), (icon: 'sun', text: 'sonnig'));
    expect(weatherSymbol(128, 'it'), (icon: 'fog', text: 'nebbia'));
    expect(weatherSymbol(null, 'de'), isNull);
    expect(weatherSymbol(99, 'de'), isNull);
  });
}
