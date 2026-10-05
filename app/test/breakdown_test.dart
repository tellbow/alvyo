import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/breakdown.dart';

void main() {
  const keys = ['paved', 'gravel', 'unknown'];

  test('the shares of what is there, none when only the unknown is known', () {
    expect(breakdownParts({'paved': 300, 'unknown': 100}, keys, unknown: 'unknown'), [
      (key: 'paved', metres: 300.0, share: 0.75),
      (key: 'unknown', metres: 100.0, share: 0.25),
    ]);
    expect(breakdownParts({'unknown': 19300}, keys, unknown: 'unknown'), isEmpty);
    expect(breakdownParts({}, keys, unknown: 'unknown'), isEmpty);
  });

  test('the three largest, the rest together', () {
    final parts = [
      for (final (i, s) in [0.05, 0.5, 0.02, 0.3, 0.13].indexed) (key: 'k$i', metres: s, share: s),
    ];
    final l = legendParts(parts);
    expect([for (final p in l.top) p.key], ['k1', 'k3', 'k4']);
    expect(l.other, closeTo(0.07, 1e-9));
  });

  test('the legs summed; off marked trails all the way', () {
    final route = {
      'legs': [
        {
          'trails': {'none': 400},
          'surfaces': {'paved': 400},
        },
        {
          'trails': {'none': 600},
          'surfaces': {'gravel': 600},
        },
      ],
    };
    expect(sumLegs(route, 'surfaces'), {'paved': 400.0, 'gravel': 600.0});
    expect(offTrail(route), isTrue);
    expect(
      offTrail({
        'legs': [
          {
            'trails': {'none': 400, 'Wanderweg': 100},
          },
        ],
      }),
      isFalse,
    );
  });

  testWidgets('the bar of a distribution has its height', (tester) async {
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
        home: const Scaffold(
          body: TrailConditions(
            route: {
              'legs': [
                {
                  'trails': {'Wanderweg': 500, 'none': 500},
                },
              ],
            },
            distanceM: 1000,
          ),
        ),
      ),
    );
    final parts = tester.widgetList<ColoredBox>(
      find.descendant(of: find.byKey(const Key('trail-conditions')), matching: find.byType(ColoredBox)),
    );
    expect(parts, hasLength(2));
    for (final p in parts) {
      expect(tester.getSize(find.byWidget(p)).height, 8);
    }
  });
}
