import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/pois.dart';

Poi _poi(String kind, double alongM, [String name = '']) => Poi.fromJson({
  'kind': kind,
  'name': name,
  'at': [9.4, 47.0],
  'along_m': alongM,
});

void main() {
  test('the fountains and restaurants of a town together, summits one each', () {
    final rows = groupPois([
      _poi('restaurant', 31, 'Perron'),
      _poi('water', 71),
      _poi('water', 73),
      _poi('restaurant', 111, 'Capannina'),
      _poi('peak', 500, 'Gonzen'),
      _poi('peak', 520, 'Alvier'),
      _poi('water', 1000),
      _poi('water', 1100), // more than 1 km after the first: a new line
      _poi('restaurant', 2500, 'Kivi'),
    ]);
    expect(
      [for (final r in rows) (r.first.kind, r.count, r.first.alongM, r.toM)],
      [
        ('restaurant', 2, 31.0, 111.0),
        ('water', 3, 71.0, 1000.0),
        ('peak', 1, 500.0, 500.0),
        ('peak', 1, 520.0, 520.0),
        ('water', 1, 1100.0, 1100.0),
        ('restaurant', 1, 2500.0, 2500.0),
      ],
    );
  });

  testWidgets('a town\'s fountains on one line of the list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: PoiList(Future.value([_poi('water', 71), _poi('water', 256), _poi('water', 940)]))),
      ),
    );
    await tester.pump();
    expect(find.text('71–940 m · Trinkwasser ×3'), findsOneWidget);
  });
}
