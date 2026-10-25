import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/navigation/tracker.dart';
import 'package:alvyo/navigation/watch.dart';
import 'package:alvyo/screens/navigate_screen.dart';

import 'navigate_test.dart' show FakeAlerts, FakeSpeech;

/// Against the local dev server (see offline_test.dart), on the iOS
/// simulator: the tours and a hike on «Sargans–Weisstannen» go through the
/// native watch bridge (WatchBridge.swift), paused and carried on on the
/// phone. With a watch simulator paired and the watch app on it, the watch
/// shows them; `--dart-define=WATCH_HOLD=20` keeps each state 20 s for a
/// look or a screenshot.
///   `flutter test integration_test/watch_test.dart -d SIMULATOR_ID`
/// With `--dart-define=WATCH_FROM_WATCH=true`, a hike waits for the watch's
/// buttons instead: the watch's UI test `testWithPhone` pauses, carries on
/// and finishes it (app/README.md).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const hold = Duration(seconds: int.fromEnvironment('WATCH_HOLD'));
  const fromWatch = bool.fromEnvironment('WATCH_FROM_WATCH');

  Future<void> waitFor(WidgetTester tester, Finder f, {Duration timeout = const Duration(seconds: 60)}) async {
    final end = DateTime.now().add(timeout);
    while (f.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $f');
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> pumpFor(WidgetTester tester, Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('the watch bridge takes the tours and the hike; pause on the phone', (tester) async {
    if (!Platform.isIOS || fromWatch) return; // only iOS has the watch app
    final api = Api('http://localhost:5173');
    await api.login('appdemo', 'sehr-geheim-123');
    final routes = await api.routes();
    final route = await api.route(routes.firstWhere((r) => r.title == 'Sargans–Weisstannen').id);

    // The bridge answers (no MissingPluginException): nothing pending.
    const channel = MethodChannel('alvyo/watch');
    expect(await channel.invokeMethod<Object?>('pendingStart'), isNull);
    await channel.invokeMethod<void>('tours', [
      for (final r in routes)
        {'id': r.id, 'title': r.title, 'distanceM': r.totals.distanceM, 'durationS': r.totals.durationS},
    ]);
    await pumpFor(tester, hold);

    final positions = StreamController<Fix>();
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
        home: NavigateScreen(
          api: api,
          route: route,
          positions: () => positions.stream,
          recordings: Directory.systemTemp.createTempSync('recordings'),
          alerts: FakeAlerts(),
          speech: FakeSpeech(),
        ),
      ),
    );
    await waitFor(tester, find.byKey(const Key('nav-pause'))); // recording
    expect(WatchLink.instance.controls, isNotNull);
    await tester.pump(const Duration(seconds: 2)); // the turns come from the server
    var t = DateTime.now().toUtc();
    for (final p in route.line.take(40)) {
      positions.add(Fix(lon: p[0], lat: p[1], ele: p[2], accuracyM: 5, time: t));
      t = t.add(const Duration(seconds: 15));
      await pumpFor(tester, const Duration(milliseconds: 100));
    }
    await waitFor(tester, find.byKey(const Key('nav-turn')));
    await pumpFor(tester, hold);

    await tester.tap(find.byKey(const Key('nav-pause')));
    await waitFor(tester, find.byKey(const Key('nav-paused')));
    await pumpFor(tester, hold);
    await tester.tap(find.byKey(const Key('nav-pause')));
    await waitFor(tester, find.byKey(const Key('nav-turn')));

    await tester.tap(find.byKey(const Key('nav-finish')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-finish-confirm')));
    await tester.pumpAndSettle();
    expect(WatchLink.instance.controls, isNull);
    await pumpFor(tester, hold); // the watch back at its tours
    await positions.close();
  });

  testWidgets('the watch\'s buttons pause, carry on and finish a hike on the phone', (tester) async {
    if (!Platform.isIOS || !fromWatch) return;
    final api = Api('http://localhost:5173');
    await api.login('appdemo', 'sehr-geheim-123');
    final routes = await api.routes();
    final route = await api.route(routes.firstWhere((r) => r.title == 'Sargans–Weisstannen').id);
    final positions = StreamController<Fix>();
    HikeSummary? result;
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
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('go'),
                onPressed: () async => result = await Navigator.of(context).push<HikeSummary>(
                  MaterialPageRoute(
                    builder: (_) => NavigateScreen(
                      api: api,
                      route: route,
                      positions: () => positions.stream,
                      recordings: Directory.systemTemp.createTempSync('recordings'),
                      alerts: FakeAlerts(),
                      speech: FakeSpeech(),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('go')));
    await waitFor(tester, find.byKey(const Key('nav-pause')));
    // A few positions, then none: the watch app, installed only now (by its
    // UI test), must get the hike all the same.
    var t = DateTime.now().toUtc();
    for (final p in route.line.take(20)) {
      positions.add(Fix(lon: p[0], lat: p[1], ele: p[2], accuracyM: 5, time: t));
      t = t.add(const Duration(seconds: 15));
      await pumpFor(tester, const Duration(milliseconds: 100));
    }
    debugPrint('waiting for the watch');
    await waitFor(tester, find.byKey(const Key('nav-paused')), timeout: const Duration(minutes: 4));
    final end = DateTime.now().add(const Duration(minutes: 1));
    while (find.byKey(const Key('nav-paused')).evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(end)) throw TestFailure('not carried on from the watch');
      await tester.pump(const Duration(milliseconds: 200));
    }
    await waitFor(tester, find.byKey(const Key('go')), timeout: const Duration(minutes: 1));
    expect(result, isNotNull, reason: 'finished from the watch');
    expect(find.byKey(const Key('nav-finish-confirm')), findsNothing);
    await positions.close();
  });
}
