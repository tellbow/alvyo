import 'package:flutter_test/flutter_test.dart';
import 'package:alvyo/sbb.dart';

void main() {
  test('the journey to a stage start on its date', () {
    final u = sbbTimetable(to: 'Weisstannen, Oberdorf', date: DateTime(2026, 7, 4), language: 'de');
    expect(u.origin + u.path, 'https://www.sbb.ch/de/kaufen/pages/fahrplan/fahrplan.xhtml');
    expect(u.queryParameters, {'nach': 'Weisstannen, Oberdorf', 'datum': '04.07.2026'});
  });

  test('searches right away when both ends are known', () {
    final u = sbbTimetable(from: 'Elm, Station', to: 'Zürich HB', language: 'en');
    expect(u.path, '/en/buying/pages/fahrplan/fahrplan.xhtml');
    expect(u.queryParameters, {'von': 'Elm, Station', 'nach': 'Zürich HB', 'suche': 'true'});
  });
}
