import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:alvyo/main.dart';

/// Against a local dev server with the demo account (see README.md) and the
/// graph with the time profiles: «Wie weit komme ich?» from a place.
///   `flutter test integration_test/reach_test.dart -d SIMULATOR_ID`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(WidgetTester tester, Finder f, {Duration timeout = const Duration(seconds: 60)}) async {
    final end = DateTime.now().add(timeout);
    while (f.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $f');
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> settle(WidgetTester tester) => tester.pump(const Duration(seconds: 1));

  testWidgets('how far one gets from Sargans', (tester) async {
    await tester.pumpWidget(AlvyoApp(key: UniqueKey()));
    await settle(tester);
    if (find.byKey(const Key('server')).evaluate().isNotEmpty) {
      await tester.enterText(find.byKey(const Key('server')), 'http://localhost:5173');
      await tester.enterText(find.byKey(const Key('login')), 'appdemo');
      await tester.enterText(find.byKey(const Key('password')), 'sehr-geheim-123');
      await tester.tap(find.byKey(const Key('submit')));
    }
    await waitFor(tester, find.byKey(const Key('reach')));
    await tester.tap(find.byKey(const Key('reach')));
    await waitFor(tester, find.byKey(const Key('place-search-open')));
    await settle(tester);

    await tester.tap(find.byKey(const Key('place-search-open')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('place-search')), 'Sargans');
    await waitFor(tester, find.byKey(const Key('place-result-0')));
    await tester.tap(find.byKey(const Key('place-result-0')));
    await waitFor(tester, find.byKey(const Key('reach-start')));
    // The answer is in once the notice has gone; the legend is below.
    await waitFor(tester, find.text('Working out how far you get …'), timeout: const Duration(seconds: 5));
    final end = DateTime.now().add(const Duration(seconds: 60));
    while (find.text('Working out how far you get …').evaluate().isNotEmpty && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byKey(const Key('reach-error')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('reach-legend-8')),
      100,
      scrollable: find.descendant(of: find.byKey(const Key('reach-panel')), matching: find.byType(Scrollable)).first,
    );
    expect(find.byKey(const Key('reach-legend-2')), findsOneWidget);
    debugPrint('READY');
    await tester.pump(const Duration(seconds: 6));
  });
}
