import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:alvyo/main.dart';

/// Against a local dev server with the demo account and the places imported
/// (`make places-import`): plans Sargans → Weisstannen by search, saves it
/// and finds it in the list. Each run saves another route.
///   `flutter test integration_test/planner_test.dart -d SIMULATOR_ID`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(WidgetTester tester, Finder f, {Duration timeout = const Duration(seconds: 60)}) async {
    final end = DateTime.now().add(timeout);
    while (f.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $f');
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('plan a route by search, save it and open it', (tester) async {
    await tester.pumpWidget(const AlvyoApp());
    await tester.pump(const Duration(seconds: 1));
    if (find.byKey(const Key('server')).evaluate().isNotEmpty) {
      await tester.enterText(find.byKey(const Key('server')), 'http://localhost:5173');
      await tester.enterText(find.byKey(const Key('login')), 'appdemo');
      await tester.enterText(find.byKey(const Key('password')), 'sehr-geheim-123');
      await tester.tap(find.byKey(const Key('submit')));
    }
    await waitFor(tester, find.byKey(const Key('plan-route')));
    await tester.tap(find.byKey(const Key('plan-route')));
    await waitFor(tester, find.byKey(const Key('place-search')));

    for (final q in ['Sargans', 'Weisstannen']) {
      await tester.enterText(find.byKey(const Key('place-search')), q);
      await waitFor(tester, find.byKey(const Key('place-result-0')));
      await tester.tap(find.byKey(const Key('place-result-0')));
      await tester.pump(const Duration(seconds: 1));
    }
    await waitFor(tester, find.byKey(const Key('planner-point-1')));
    // Legs take a moment; the save button is there once both points are.
    final save = find.byKey(const Key('planner-save'));
    await tester.ensureVisible(save);
    final end = DateTime.now().add(const Duration(seconds: 60));
    while (tester.widget<FilledButton>(save).onPressed == null) {
      if (DateTime.now().isAfter(end)) throw TestFailure('the leg was not computed');
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byKey(const Key('planner-totals')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2)); // for a screenshot

    await tester.tap(save);
    await waitFor(tester, find.byKey(const Key('planner-title')));
    final title = 'Geplant ${DateTime.now().millisecondsSinceEpoch}';
    await tester.enterText(find.byKey(const Key('planner-title')), title);
    await tester.tap(find.byKey(const Key('planner-save-confirm')));

    // The saved route opens, ready to keep offline and to hike.
    await waitFor(tester, find.byKey(const Key('nav-start')));
    expect(find.text(title), findsOneWidget);
    await tester.pageBack();
    await waitFor(tester, find.text(title));
  });
}
