import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/main.dart';
import 'package:alvyo/navigation/alerts.dart';
import 'package:alvyo/navigation/speech.dart';
import 'package:alvyo/navigation/tracker.dart';
import 'package:alvyo/screens/navigate_screen.dart';
import 'package:alvyo/theme.dart';

/// Walks the app through the App Store screenshots' states and prints
/// `SHOT <name>` at each; capture.sh takes the picture. Not one of the
/// integration tests: capture.sh copies it into integration_test/ for the
/// run. Needs the account from seed.sh and the simulator in the language
/// given as LANG.

class _QuietAlerts extends Alerts {
  @override
  Future<void> init() async {}
  @override
  Future<void> offRoute(String title, String body) async {}
  @override
  Future<void> clear() async {}
}

class _QuietSpeech extends Speech {
  @override
  Future<void> say(String text, String language) async {}
}

const _server = 'http://localhost:5173';
const _login = 'storeshots';
const _password = 'store-shots-2026';
const _shots = String.fromEnvironment('SHOTS', defaultValue: 'route,nav,reach,journey,weather,discover');
const _lang = String.fromEnvironment('LANG', defaultValue: 'de');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(WidgetTester tester, Finder f, {Duration timeout = const Duration(seconds: 60)}) async {
    final end = DateTime.now().add(timeout);
    while (f.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $f');
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  // Time for the map tiles, then hold still for the picture.
  Future<void> shot(WidgetTester tester, String name, {int wait = 8}) async {
    await tester.pump(Duration(seconds: wait));
    debugPrint('SHOT $name');
    await tester.pump(const Duration(seconds: 6));
  }

  // A fresh app for each state: the saved session skips the login.
  Future<void> fresh(WidgetTester tester) async {
    await tester.pumpWidget(AlvyoApp(key: UniqueKey()));
    await waitFor(tester, find.byKey(const Key('tab-profile')));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tab(WidgetTester tester, String key) async {
    await waitFor(tester, find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> openRoute(WidgetTester tester, String title) async {
    await fresh(tester);
    await tab(tester, 'tab-tours');
    await waitFor(tester, find.text(title));
    await tester.tap(find.text(title));
    await waitFor(tester, find.byKey(const Key('route-stats')));
  }

  testWidgets('App Store screenshots', (tester) async {
    final want = _shots.split(',');
    WidgetsApp.debugAllowBannerOverride = false;
    await tester.pumpWidget(AlvyoApp(key: UniqueKey()));
    await tester.pump(const Duration(seconds: 1));
    final login = find.byKey(const Key('server'));
    await waitFor(
      tester,
      find.byWidgetPredicate((w) => w.key == const Key('server') || w.key == const Key('tab-profile')),
    );
    if (login.evaluate().isNotEmpty) {
      await tester.enterText(login, _server);
      await tester.enterText(find.byKey(const Key('login')), _login);
      await tester.enterText(find.byKey(const Key('password')), _password);
      await tester.tap(find.byKey(const Key('submit')));
    }
    await waitFor(tester, find.byKey(const Key('tab-profile')));

    if (want.contains('route')) {
      await openRoute(tester, 'Eiger Trail');
      await shot(tester, 'route', wait: 10);
    }

    if (want.contains('reach')) {
      await fresh(tester);
      await tab(tester, 'tab-discover');
      await tester.tap(find.byKey(const Key('tool-reach')));
      await waitFor(tester, find.byKey(const Key('place-search-open')));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('place-search-open')));
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(find.byKey(const Key('place-search')), 'Grindelwald');
      await waitFor(tester, find.byKey(const Key('place-result-0')));
      await tester.tap(find.byKey(const Key('place-result-0')));
      final busy = find.text(lookupAppLocalizations(const Locale(_lang)).reachBusy);
      await waitFor(tester, busy, timeout: const Duration(seconds: 10));
      final end = DateTime.now().add(const Duration(seconds: 90));
      while (busy.evaluate().isNotEmpty && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await shot(tester, 'reach');
    }

    if (want.contains('journey')) {
      await fresh(tester);
      await tab(tester, 'tab-tours');
      await tester.tap(find.byKey(const Key('tours-kind-journeys')));
      await waitFor(tester, find.text('Aletsch Panoramaweg'));
      await tester.tap(find.text('Aletsch Panoramaweg'));
      await waitFor(tester, find.byKey(const Key('journey-save')));
      await shot(tester, 'journey', wait: 10);
    }

    if (want.contains('weather')) {
      // The map stays on top; the panel below scrolls up to the weather.
      await openRoute(tester, '5-Seenweg Zermatt');
      await tester.pump(const Duration(seconds: 3));
      await tester.scrollUntilVisible(find.byKey(const Key('weather')), 200, scrollable: find.byType(Scrollable).last);
      await tester.drag(find.byKey(const Key('weather')), const Offset(0, -700));
      await shot(tester, 'weather');
    }

    if (want.contains('discover')) {
      // The official routes around Grindelwald (the local database also
      // holds the tests' public routes).
      await fresh(tester);
      await tab(tester, 'tab-discover');
      await tester.enterText(find.byKey(const Key('discover-search')), 'Grindelwald');
      final found = find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('found-'),
      );
      await waitFor(tester, found);
      await tester.tap(found.first);
      await waitFor(tester, find.byKey(const Key('discover-origin')));
      await tester.pump(const Duration(seconds: 2));
      // In French and Italian the filters run off the screen.
      await tester.ensureVisible(find.byKey(const Key('discover-origin')));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('discover-origin')));
      await waitFor(tester, find.byKey(const Key('discover-origin-only')));
      await tester.tap(find.byKey(const Key('discover-origin-only')).last);
      await waitFor(tester, find.byKey(const Key('discover-item-0')));
      await shot(tester, 'discover', wait: 10);
    }

    // Last: navigation on made-up positions, a third of the way along.
    if (want.contains('nav')) {
      final api = Api(_server);
      await api.login(_login, _password);
      final summary = (await api.routes()).firstWhere((r) => r.title == 'Eiger Trail');
      final route = await api.route(summary.id);
      final positions = StreamController<Fix>();
      final cut = (route.line.length * 0.35).round();
      await tester.pumpWidget(
        MaterialApp(
          // The app's look: without it Flutter's default purple shows.
          theme: alvyoTheme(Brightness.light),
          locale: const Locale(_lang),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: NavigateScreen(
            api: api,
            route: route,
            positions: () => positions.stream,
            recordings: Directory.systemTemp.createTempSync('recordings'),
            alerts: _QuietAlerts(),
            speech: _QuietSpeech(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      var t = DateTime.now().toUtc().subtract(Duration(minutes: cut));
      for (final p in route.line.take(cut)) {
        positions.add(Fix(lon: p[0], lat: p[1], ele: p[2], accuracyM: 5, time: t));
        t = t.add(const Duration(minutes: 1));
        await tester.pump(const Duration(milliseconds: 40));
      }
      await waitFor(tester, find.byKey(const Key('nav-progress')));
      await shot(tester, 'nav');
    }
  });
}
