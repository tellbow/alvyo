import 'package:flutter_test/flutter_test.dart';
import 'package:alvyo/screens/details.dart';

void main() {
  test('a GPX file keeps the dash and words of its title', () {
    expect(gpxFileName('Sargans – Weisstannen', 'r1'), 'Sargans - Weisstannen.gpx');
    expect(gpxFileName('Sargans–Weisstannen', 'r1'), 'Sargans-Weisstannen.gpx');
    expect(gpxFileName('Via Alpina: 1/20 «Gaflei»', 'j1', journey: true), 'Via Alpina 1 20 Gaflei.zip');
    expect(gpxFileName('???', 'r1'), 'r1.gpx');
  });
}
