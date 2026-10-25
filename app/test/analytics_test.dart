import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/analytics.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/screens/home_screen.dart';

/// Records what would go to Google Analytics.
class FakeSink implements AnalyticsSink {
  final collecting = <bool>[];
  final screens = <String>[];
  @override
  Future<void> collect(bool on) async => collecting.add(on);
  @override
  Future<void> screen(String name) async => screens.add(name);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('nothing goes to Google before «Akzeptieren», and nothing after «Ablehnen»', () async {
    final sink = FakeSink();
    final analytics = Analytics(sink: sink);
    await analytics.loaded;
    expect(analytics.consent.value, isNull);
    analytics.screen('route');
    expect(sink.screens, isEmpty);

    await analytics.setConsent(true);
    analytics.screen('route');
    expect(sink.collecting, [true]);
    expect(sink.screens, ['route']);

    await analytics.setConsent(false);
    analytics.screen('journey');
    expect(sink.collecting, [true, false]);
    expect(sink.screens, ['route']);
  });

  test('the choice is kept: collecting again at the next start, or not asked again', () async {
    await Analytics(sink: FakeSink()).setConsent(true);
    final sink = FakeSink();
    final next = Analytics(sink: sink);
    await next.loaded;
    expect(next.consent.value, isTrue);
    expect(sink.collecting, [true]);

    await next.setConsent(false);
    final after = Analytics(sink: FakeSink());
    await after.loaded;
    expect(after.consent.value, isFalse);
  });

  test('a build without Firebase settings (debug, tests, forks) measures nothing', () async {
    final analytics = Analytics();
    await analytics.loaded;
    expect(analytics.active, isFalse);
  });

  group('the home screen', () {
    final client = MockClient((req) async {
      final body = switch (req.url.path) {
        '/api/v1/routes' => {'routes': <Object>[]},
        '/api/v1/journeys' => {'journeys': <Object>[]},
        '/api/v1/feed' => {'items': <Object>[]},
        '/api/v1/shared' => {'routes': <Object>[], 'journeys': <Object>[], 'collections': <Object>[]},
        '/api/v1/me' => {'id': 'u1', 'username': 'wodan', 'display_name': 'Wodan', 'speed_factor': 1},
        _ => null,
      };
      if (body == null) return http.Response('', 404);
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    });

    // The tabs keep spinners going: pumpAndSettle never settles.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> pump(WidgetTester tester, Analytics analytics) async {
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
          home: HomeScreen(
            api: Api('https://alvyo.test', token: 't', client: client),
            onLogout: () {},
            analytics: analytics,
            planModes: (mode, saved) => Text('plan ${mode.name}'),
          ),
        ),
      );
      await tester.runAsync(() => analytics.loaded);
      await settle(tester);
    }

    testWidgets('asks once; the answer counts from then on and can be changed in Profil', (tester) async {
      // Tall enough for the whole profile, above the floating bar.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final sink = FakeSink();
      final analytics = Analytics(sink: sink);
      await pump(tester, analytics);
      expect(find.byKey(const Key('statistics-sheet')), findsOneWidget);
      // Asked before anything was sent: not even the first tab.
      expect(sink.screens, isEmpty);
      await tester.tap(find.byKey(const Key('statistics-accept')));
      await settle(tester);
      expect(find.byKey(const Key('statistics-sheet')), findsNothing);
      expect(analytics.consent.value, isTrue);

      await tester.tap(find.byKey(const Key('tab-profile')));
      await settle(tester);
      expect(sink.screens, ['profile']);
      final tile = find.byKey(const Key('statistics'));
      expect(find.descendant(of: tile, matching: find.text('Zugestimmt')), findsOneWidget);
      await tester.tap(tile);
      await settle(tester);
      await tester.tap(find.byKey(const Key('statistics-decline')));
      await settle(tester);
      expect(sink.collecting, [true, false]);
      expect(find.descendant(of: tile, matching: find.text('Abgelehnt')), findsOneWidget);
    });

    testWidgets('not asked when the answer is known, or when the build measures nothing', (tester) async {
      FlutterSecureStorage.setMockInitialValues({'analytics': 'denied'});
      await pump(tester, Analytics(sink: FakeSink()));
      expect(find.byKey(const Key('statistics-sheet')), findsNothing);

      FlutterSecureStorage.setMockInitialValues({});
      await pump(tester, Analytics());
      expect(find.byKey(const Key('statistics-sheet')), findsNothing);
    });
  });
}
