import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/main.dart';
import 'package:alvyo/screens/journey_screen.dart';
import 'package:alvyo/offline/packs.dart';

import 'offline_test.dart' show OfflineSession;

/// Against a local dev server with the demo account's journey «Via Alpina»
/// (stages «Gaflei – Sargans» and «Sargans – Weisstannen», see README.md):
/// opens it, saves all stages offline, then opens it and a stage without a
/// connection.
///   `flutter test integration_test/journey_test.dart -d SIMULATOR_ID`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(WidgetTester tester, Finder f, {Duration timeout = const Duration(seconds: 60)}) async {
    final end = DateTime.now().add(timeout);
    while (f.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $f');
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('a journey: its stages, all saved offline, opened without a connection', (tester) async {
    // Start over: nothing of the journey saved.
    final api = Api('http://localhost:5173');
    await api.login('appdemo', 'sehr-geheim-123');
    final id = (await api.journeys()).firstWhere((j) => j.title == 'Via Alpina').id;
    final stageRoutes = [for (final s in (await api.journey(id)).stages) ?s.routeId];
    final store = await PackStore.open();
    for (final r in stageRoutes) {
      await store.delete(r);
    }
    final kept = File('${store.root.path}/journey-$id.json');
    if (kept.existsSync()) kept.deleteSync();

    await tester.pumpWidget(const AlvyoApp());
    await tester.pump(const Duration(seconds: 1));
    if (find.byKey(const Key('server')).evaluate().isNotEmpty) {
      await tester.enterText(find.byKey(const Key('server')), 'http://localhost:5173');
      await tester.enterText(find.byKey(const Key('login')), 'appdemo');
      await tester.enterText(find.byKey(const Key('password')), 'sehr-geheim-123');
      await tester.tap(find.byKey(const Key('submit')));
    }
    await waitFor(tester, find.byKey(const Key('tab-tours')));
    await tester.tap(find.byKey(const Key('tab-tours')));
    await waitFor(tester, find.text('Via Alpina'));
    await tester.pump(const Duration(seconds: 1)); // the tabs slide
    await tapAboveBar(tester, find.text('Via Alpina'));

    await waitFor(tester, find.text('Gaflei – Sargans'));
    expect(find.text('Sargans – Weisstannen'), findsOneWidget);
    expect(find.textContaining('Gaflei, Klinik → Sargans'), findsOneWidget);
    final started = DateTime.now();
    await tester.tap(find.byKey(const Key('journey-save')));
    await waitFor(tester, find.byKey(const Key('journey-saving')));
    await waitFor(tester, find.byKey(const Key('journey-saved')), timeout: const Duration(minutes: 8));
    debugPrint('saving both stages took ${DateTime.now().difference(started).inSeconds} s');
    expect((await store.savedJourney(id))!.stages, hasLength(2));
    for (final r in stageRoutes) {
      expect(await store.saved(r), isNotNull);
    }
    expect(find.byIcon(Icons.offline_pin), findsNWidgets(3)); // the header and both stages

    // Without a connection: the saved journey, and a stage on its offline map.
    await tester.pumpWidget(AlvyoApp(key: UniqueKey(), session: OfflineSession()));
    await waitFor(tester, find.byKey(const Key('tab-tours')));
    await tester.tap(find.byKey(const Key('tab-tours')));
    await waitFor(tester, find.byKey(const Key('tours-offline')));
    await tester.pump(const Duration(seconds: 1));
    await tapAboveBar(tester, find.text('Via Alpina'));
    // The stage on the journey's page: Touren lists a route of that name too.
    final stage = find.descendant(of: find.byType(JourneyScreen), matching: find.text('Sargans – Weisstannen'));
    await waitFor(tester, stage);
    await tester.pump(const Duration(seconds: 1)); // the page slides in
    await tester.tap(stage);
    await waitFor(tester, find.byKey(const Key('offline-remove')));
    expect(find.byKey(const Key('nav-start')), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // for a screenshot
  });
}

/// Taps [f] in a list that runs under the floating bar: scrolled only when
/// it is not clear of the bar (a short list scrolled anyway bounces back).
Future<void> tapAboveBar(WidgetTester tester, Finder f) async {
  final view = tester.view;
  final clear = view.physicalSize.height / view.devicePixelRatio - 160;
  if (tester.getCenter(f).dy > clear) {
    final list = find.ancestor(of: f, matching: find.byType(Scrollable)).first;
    await tester.ensureVisible(f);
    await tester.pump(const Duration(seconds: 1));
    final y = tester.getCenter(f).dy;
    if (y > clear) await tester.drag(list, Offset(0, clear - y));
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.tap(f);
}
