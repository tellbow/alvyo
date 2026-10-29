import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/screens/tiles.dart';

void main() {
  // Who sees one's route, on its card (feedback issue 45); not on others'.
  testWidgets('one\'s own tour shows who sees it', (tester) async {
    final route = RouteSummary.fromJson({
      'id': 'r1',
      'title': 'Gratweg',
      'owner_username': 'wodan',
      'visibility': 'public',
      'totals': {
        'distance_m': 5000,
        'ascent_m': 300,
        'descent_m': 300,
        'duration_s': 5400,
        'sac_grade': 1,
        'sac_max': 1,
      },
    });
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
        home: Scaffold(
          body: Column(
            children: [
              RouteTile(route: route, onTap: () {}),
              RouteTile(route: route, owner: 'anna', onTap: () {}),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Öffentlich'), findsOneWidget);
    expect(find.byTooltip('Alle, auch ohne Konto, und auffindbar'), findsOneWidget);
  });
}
