import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/protected_areas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('de'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: ListView(children: [child])),
);

SnowAlong _snow(Map<String, dynamic> j) => SnowAlong.fromJson({
  'date': '2026-10-18',
  'attribution': "Generated using European Union's Copernicus Land Monitoring Service information",
  'slopes': true,
  ...j,
});

void main() {
  testWidgets('snow along: how much and how steep, a stretch shown on the map', (tester) async {
    List<List<List<double>>>? shown;
    final snow = _snow({
      'snow_m': 1180,
      'steep_m': 310,
      'patches_m': 420,
      'stretches': [
        {
          'from_m': 2300,
          'to_m': 3100,
          'steep_m': 310,
          'line': [
            [8.0, 46.6],
            [8.01, 46.61],
          ],
        },
        {
          'from_m': 5000,
          'to_m': 5434,
          'steep_m': 0,
          'line': [
            [8.02, 46.62],
            [8.03, 46.63],
          ],
        },
      ],
    });
    await tester.pumpWidget(_app(SnowAlongView(Future.value(snow), onShow: (p) => shown = p)));
    await tester.pump();

    // The amount beside the count; the rest in a sheet.
    expect(find.text('Schnee unterwegs'), findsOneWidget);
    expect(find.text('2 anzeigen · 1.2 km Schnee, 300 m steil'), findsOneWidget);
    await tester.tap(find.textContaining('2 anzeigen'));
    await tester.pumpAndSettle();
    expect(
      find.text('Führt über 1.2 km Schnee, davon 300 m steiler als 30°. Dazu Schneeflecken auf 400 m.'),
      findsOneWidget,
    );
    expect(find.text('Nach 2.3 km: 800 m Schnee · davon 300 m steiler als 30°'), findsOneWidget);
    expect(find.text('Nach 5.0 km: 450 m Schnee'), findsOneWidget);
    expect(find.textContaining('Schneebedeckung am 18. Oktober.'), findsOneWidget);
    // The credit at the end of the sheet.
    await tester.scrollUntilVisible(find.textContaining('Copernicus'), 100, scrollable: find.byType(Scrollable).last);
    expect(find.textContaining('Copernicus'), findsOneWidget);

    // On the map: the sheet closes, the stretch is shown.
    await tester.tap(find.text('Auf der Karte zeigen').first);
    await tester.pumpAndSettle();
    expect(find.text('Nach 5.0 km: 450 m Schnee'), findsNothing);
    expect(shown, [
      [
        [8.0, 46.6],
        [8.01, 46.61],
      ],
    ]);
  });

  testWidgets('snow along: patches only, or nothing', (tester) async {
    await tester.pumpWidget(
      _app(SnowAlongView(Future.value(_snow({'snow_m': 0, 'patches_m': 640, 'stretches': <Object>[]})))),
    );
    await tester.pump();
    expect(find.text('Schneeflecken auf 650 m, Stand 18. Oktober.'), findsOneWidget);
    expect(find.textContaining('anzeigen'), findsNothing);

    await tester.pumpWidget(
      _app(SnowAlongView(Future.value(_snow({'snow_m': 0, 'patches_m': 0, 'stretches': <Object>[]})))),
    );
    await tester.pump();
    expect(find.text('Schnee unterwegs'), findsNothing);
  });
}
