import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:odysgeh/api.dart';
import 'package:odysgeh/l10n/app_localizations.dart';
import 'package:odysgeh/navigation/alerts.dart';
import 'package:odysgeh/navigation/tracker.dart';
import 'package:odysgeh/screens/navigate_screen.dart';

/// Records warnings instead of showing notifications.
class FakeAlerts extends Alerts {
  final shown = <String>[];
  var cleared = 0;
  @override
  Future<void> init() async {}
  @override
  Future<void> offRoute(String title, String body) async => shown.add(body);
  @override
  Future<void> clear() async => cleared++;
}

/// Against the local dev server (see offline_test.dart): walks along
/// «Sargans–Weisstannen» with made-up positions, strays 100 m off the route
/// and comes back, then finishes the hike.
///   `flutter test integration_test/navigate_test.dart -d SIMULATOR_ID`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(WidgetTester tester, Finder f, {Duration timeout = const Duration(seconds: 60)}) async {
    final end = DateTime.now().add(timeout);
    while (f.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $f');
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('hike a route: progress, off the route and back, finish', (tester) async {
    final api = Api('http://localhost:5173');
    await api.login('appdemo', 'sehr-geheim-123');
    final summary = (await api.routes()).firstWhere((r) => r.title == 'Sargans–Weisstannen');
    final route = await api.route(summary.id);
    final recordings = Directory.systemTemp.createTempSync('recordings');
    final alerts = FakeAlerts();

    // Every 25th point of the line (the line has a point about every 20 m)
    // and its end; positions 10 to 12 are 100 m to the north.
    final positions = StreamController<Fix>();
    final walk = [for (var i = 0; i < route.line.length; i += 25) route.line[i], route.line.last];
    Future<void> send() async {
      var t = DateTime.now().toUtc();
      for (var i = 0; i < walk.length; i++) {
        final off = i >= 10 && i <= 12 ? 100 / 111320 : 0.0;
        positions.add(Fix(lon: walk[i][0], lat: walk[i][1] + off, ele: walk[i][2], accuracyM: 5, time: t));
        t = t.add(const Duration(minutes: 1));
        await Future<void>.delayed(const Duration(milliseconds: 150));
        if (i == 11) await Future<void>.delayed(const Duration(seconds: 3)); // time for a screenshot
      }
    }

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
                onPressed: () async {
                  result = await Navigator.of(context).push<HikeSummary>(
                    MaterialPageRoute(
                      builder: (_) => NavigateScreen(
                        api: api,
                        route: route,
                        positions: () => positions.stream,
                        recordings: recordings,
                        alerts: alerts,
                      ),
                    ),
                  );
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('go')));
    await waitFor(tester, find.text('Warte auf GPS …'));
    unawaited(send());

    await waitFor(tester, find.byKey(const Key('nav-progress')));
    await waitFor(tester, find.byKey(const Key('nav-off-route')));
    expect(alerts.shown.single, matches(RegExp(r'^\d+ m neben der Route$')));
    await waitFor(tester, find.byKey(const Key('nav-progress')));
    final end = DateTime.now().add(const Duration(seconds: 60));
    while (find.byKey(const Key('nav-off-route')).evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(end)) throw TestFailure('still off the route');
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(alerts.cleared, greaterThan(0));
    await waitFor(tester, find.text('Ziel erreicht'), timeout: const Duration(seconds: 90));
    debugPrint('walked ${walk.length} positions of ${route.line.length}');

    await tester.tap(find.byKey(const Key('nav-finish')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-finish-confirm')));
    await waitFor(tester, find.byKey(const Key('go')));
    expect(result, isNotNull);
    expect(result!.distanceM, greaterThan(route.totals.distanceM * 0.8));
    // The made-up positions are a minute apart.
    expect(result!.duration.inMinutes, inInclusiveRange(walk.length - 1, walk.length));
    final done = Directory('${recordings.path}/done').listSync();
    expect(done, hasLength(1));
    debugPrint('recorded ${result!.distanceM.round()} m in ${result!.duration.inMinutes} min');
  });
}
