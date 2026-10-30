import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alvyo/breakdown.dart';
import 'package:alvyo/l10n/app_localizations.dart';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('de'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

// Feedback issue 71.
void main() {
  testWidgets('the trail legend shows the markings, «Kein Wanderweg» its dot', (tester) async {
    await tester.pumpWidget(
      _app(
        const TrailConditions(
          route: {
            'legs': [
              {
                'trails': {'Wanderweg': 600.0, 'Alpinwanderweg': 300.0, 'none': 100.0},
              },
            ],
          },
          distanceM: 1000,
        ),
      ),
    );
    expect(find.byKey(const Key('trail-mark-Wanderweg')), findsOneWidget);
    expect(find.byKey(const Key('trail-mark-Alpinwanderweg')), findsOneWidget);
    expect(find.textContaining('Kein Wanderweg'), findsOneWidget);
  });
}
