import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/main.dart';

/// Against a local dev server with GraphHopper and the places imported (see
/// offline_test.dart for the demo account): plans Thun → Zermatt in five
/// days on the journeys tab, suggests several ways, takes the second, goes
/// on along another way where one shares a night, and creates the journey
/// (deleted again at the end).
///   `flutter test integration_test/journey_plan_test.dart -d SIMULATOR_ID`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(WidgetTester tester, Finder f, {Duration timeout = const Duration(seconds: 60)}) async {
    final end = DateTime.now().add(timeout);
    while (f.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $f');
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('plan a journey: several ways, one put together, created', (tester) async {
    const server = 'http://localhost:5173';
    final title = 'App-Plan ${DateTime.now().millisecondsSinceEpoch}';

    await tester.pumpWidget(const AlvyoApp());
    await tester.pump(const Duration(seconds: 1));
    if (find.byKey(const Key('server')).evaluate().isNotEmpty) {
      await tester.enterText(find.byKey(const Key('server')), server);
      await tester.enterText(find.byKey(const Key('login')), 'appdemo');
      await tester.enterText(find.byKey(const Key('password')), 'sehr-geheim-123');
      await tester.tap(find.byKey(const Key('submit')));
    }
    await waitFor(tester, find.byKey(const Key('tab-journeys')));
    await tester.tap(find.byKey(const Key('tab-journeys')));
    await waitFor(tester, find.byKey(const Key('journey-plan')));
    await tester.pump(const Duration(seconds: 1)); // the tabs slide
    await tester.tap(find.byKey(const Key('journey-plan')));
    await waitFor(tester, find.byKey(const Key('jplan-panel')));
    await tester.pump(const Duration(seconds: 2)); // the map loads

    final panel = find.descendant(of: find.byKey(const Key('jplan-panel')), matching: find.byType(Scrollable)).first;
    Future<void> show(Finder f) => tester.scrollUntilVisible(f, 200, scrollable: panel);

    Future<void> pick(String q) async {
      await show(find.byKey(const Key('place-search')));
      await tester.enterText(find.byKey(const Key('place-search')), q);
      await waitFor(tester, find.byKey(const Key('place-result-0')));
      await tester.tap(find.byKey(const Key('place-result-0')));
      await tester.pump(const Duration(milliseconds: 500));
    }

    await pick('Thun');
    await pick('Zermatt');
    expect(find.byKey(const Key('jplan-point-1')), findsOneWidget);

    await show(find.byKey(const Key('jplan-days')));
    await tester.enterText(find.byKey(const Key('jplan-days')), '5');
    await show(find.byKey(const Key('jplan-suggest')));
    await tester.tap(find.byKey(const Key('jplan-suggest')));
    await waitFor(tester, find.byKey(const Key('jplan-way-1')), timeout: const Duration(seconds: 90));
    expect(find.text('Weg 1: direkt'), findsOneWidget);

    // The second way.
    await show(find.byKey(const Key('jplan-way-1')));
    await tester.tap(find.byKey(const Key('jplan-way-1')));
    await tester.pump(const Duration(seconds: 1));
    await show(find.byKey(const Key('jplan-stage-0')));
    expect(find.byKey(const Key('jplan-summary')), findsOneWidget);

    // Where it shares a night with another way, go on along that one.
    final switchButtons = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('jplan-switch-'),
    );
    if (switchButtons.evaluate().isNotEmpty) {
      await tester.tap(switchButtons.first);
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining(' · Weg '), findsWidgets);
    } else {
      debugPrint('no shared night between the ways');
    }

    await show(find.byKey(const Key('jplan-title')));
    expect(tester.widget<TextField>(find.byKey(const Key('jplan-title'))).controller!.text, isNotEmpty);
    await tester.enterText(find.byKey(const Key('jplan-title')), title);
    await tester.pump();
    await show(find.byKey(const Key('jplan-create')));
    await tester.tap(find.byKey(const Key('jplan-create')));
    await waitFor(tester, find.text(title));
    await tester.pump(const Duration(seconds: 3)); // for a screenshot

    // Not kept in the demo account.
    final api = Api(server);
    await api.login('appdemo', 'sehr-geheim-123');
    final id = (await api.journeys()).firstWhere((j) => j.title == title).id;
    final deleted = await http.delete(
      Uri.parse('$server/api/v1/journeys/$id'),
      headers: {'Authorization': 'Bearer ${api.token}'},
    );
    expect(deleted.statusCode, lessThan(300));
  });
}
