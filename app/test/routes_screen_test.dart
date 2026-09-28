import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/screens/routes_screen.dart';
import 'package:alvyo/theme.dart';

void main() {
  late Directory support;
  setUpAll(() {
    support = Directory.systemTemp.createTempSync('support');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => support.path,
    );
  });
  tearDownAll(() => support.deleteSync(recursive: true));

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

  Future<void> until(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 100 && f.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pump(WidgetTester tester, Brightness brightness, VoidCallback onLogout) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        theme: alvyoTheme(brightness),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: RoutesScreen(
          api: Api('https://alvyo.test', token: 't', client: client),
          onLogout: onLogout,
        ),
      ),
    );
    await until(tester, find.text('Noch keine Routen. Plane sie auf der Website.'));
  }

  for (final brightness in Brightness.values) {
    testWidgets('the bar: journeys, the record button, the feed and the profile ($brightness)', (tester) async {
      var loggedOut = false;
      await pump(tester, brightness, () => loggedOut = true);
      expect(find.text('Meine Routen'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tab-journeys')));
      await until(tester, find.text('Etappentouren'));
      expect(find.text('Etappentouren'), findsOneWidget);

      // No hike in progress: where one is started.
      await tester.tap(find.byKey(const Key('record')));
      await until(tester, find.byType(SnackBar));
      expect(
        find.text('Wähle eine Route und tippe auf «Wanderung starten», um die Wanderung aufzuzeichnen.'),
        findsOneWidget,
      );
      expect(find.text('Meine Routen'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tab-feed')));
      await until(tester, find.byKey(const Key('feed-empty')));
      expect(find.byKey(const Key('feed-empty')), findsOneWidget);

      await tester.tap(find.byKey(const Key('tab-profile')));
      await until(tester, find.text('@wodan'));
      expect(find.text('Wodan'), findsOneWidget);
      expect(find.text('Server: alvyo.test'), findsOneWidget);
      // Clear of the floating bar.
      final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.byKey(const Key('logout')), 200, scrollable: list);
      await tester.drag(list, const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logout')));
      expect(loggedOut, isTrue);
    });
  }
}
