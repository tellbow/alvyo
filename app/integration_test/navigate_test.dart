import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/navigation/alerts.dart';
import 'package:alvyo/navigation/speech.dart';
import 'package:alvyo/navigation/tracker.dart';
import 'package:alvyo/screens/navigate_screen.dart';

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

/// Records what would be said.
class FakeSpeech extends Speech {
  final said = <String>[];
  @override
  Future<void> say(String text, String language) async => said.add('$language: $text');
}

/// Against the local dev server (see offline_test.dart): walks along
/// «Sargans–Weisstannen» with made-up positions, strays 100 m off the route
/// and comes back, then finishes the hike; and walks the start point by
/// point, told where to turn.
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

  Widget app(Widget screen) => MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: screen,
  );

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
      app(
        Builder(
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
                        speech: FakeSpeech(),
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
    // Sent once the map has followed (on Android that waits for the glide).
    while (alerts.shown.isEmpty) {
      await tester.pump(const Duration(milliseconds: 100));
    }
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

  testWidgets('turn by turn: the next turn shown, and said ahead and at it', (tester) async {
    final api = Api('http://localhost:5173');
    await api.login('appdemo', 'sehr-geheim-123');
    final summary = (await api.routes()).firstWhere((r) => r.title == 'Sargans–Weisstannen');
    final route = await api.route(summary.id);
    final speech = FakeSpeech();
    final positions = StreamController<Fix>();
    // The first 2 km, a position every point of the line (about 20 m).
    Future<void> send() async {
      var t = DateTime.now().toUtc();
      for (final p in route.line.take(100)) {
        positions.add(Fix(lon: p[0], lat: p[1], ele: p[2], accuracyM: 5, time: t));
        t = t.add(const Duration(seconds: 15));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    await tester.pumpWidget(
      app(
        NavigateScreen(
          api: api,
          route: route,
          positions: () => positions.stream,
          recordings: Directory.systemTemp.createTempSync('recordings'),
          alerts: FakeAlerts(),
          speech: speech,
        ),
      ),
    );
    await waitFor(tester, find.text('Warte auf GPS …'));
    await tester.pump(const Duration(seconds: 2)); // the turns come from the server
    unawaited(send());
    await waitFor(tester, find.byKey(const Key('nav-turn')));
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (!speech.said.any((s) => !s.startsWith('de: In '))) {
      if (DateTime.now().isAfter(end)) throw TestFailure('said only ${speech.said}');
      await tester.pump(const Duration(milliseconds: 200));
    }
    debugPrint('said: ${speech.said}');
    expect(speech.said.first, matches(RegExp(r'^de: In \d+0 Metern [a-z]')));
    // Voice off: nothing more is said.
    await tester.tap(find.byKey(const Key('nav-voice')));
    final n = speech.said.length;
    await tester.pump(const Duration(seconds: 5));
    expect(speech.said, hasLength(n));
    await tester.tap(find.byKey(const Key('nav-finish')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-finish-confirm')));
    await tester.pumpAndSettle();
  });

  testWidgets('the native voice takes a prompt (iOS and Android)', (tester) async {
    // The channel itself, so that a missing channel or a refused audio
    // session fails (Speech keeps quiet about both).
    await const MethodChannel('alvyo/speech').invokeMethod<void>('say', {'text': 'Links abbiegen', 'language': 'de'});
    await const MethodChannel('alvyo/speech').invokeMethod<void>('say', {'text': 'Turn left', 'language': 'en'});
  });
}
