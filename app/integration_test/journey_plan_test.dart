import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
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
    await waitFor(tester, find.byKey(const Key('tab-plan')));
    await tester.tap(find.byKey(const Key('tab-plan')));
    await waitFor(tester, find.byKey(const Key('plan-mode-multi')));
    await tester.tap(find.byKey(const Key('plan-mode-multi')));
    await waitFor(tester, find.byKey(const Key('jplan-panel')));
    await tester.pump(const Duration(seconds: 2)); // the map loads

    final panel = find.descendant(of: find.byKey(const Key('jplan-panel')), matching: find.byType(Scrollable)).first;
    // Built is not yet in sight: then wholly into the panel.
    Future<void> show(Finder f) async {
      await tester.scrollUntilVisible(f, 200, scrollable: panel);
      await tester.ensureVisible(f);
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> pick(String q) async {
      await show(find.byKey(const Key('place-search-open')));
      await tester.tap(find.byKey(const Key('place-search-open')));
      await waitFor(tester, find.byKey(const Key('place-search')));
      await tester.enterText(find.byKey(const Key('place-search')), q);
      await waitFor(tester, find.byKey(const Key('place-result-0')));
      await tester.tap(find.byKey(const Key('place-result-0')));
      await tester.pump(const Duration(seconds: 1)); // the search page closes
    }

    await pick('Thun');
    await pick('Zermatt');
    expect(find.byKey(const Key('jplan-point-1')), findsOneWidget);

    await show(find.byKey(const Key('jplan-days')));
    await tester.enterText(find.byKey(const Key('jplan-days')), '5');
    // As a user does: a tap outside closes the number pad over the buttons.
    await tester.tapAt(tester.getTopLeft(find.byKey(const Key('jplan-panel'))) + const Offset(4, 4));
    await tester.pump(const Duration(milliseconds: 500));
    await show(find.byKey(const Key('jplan-suggest')));
    await tester.tap(find.byKey(const Key('jplan-suggest')));
    // Planning takes a while; the ways come below the buttons.
    await tester.pump(const Duration(seconds: 1));
    final end = DateTime.now().add(const Duration(seconds: 90));
    while (find.byKey(const Key('jplan-busy')).evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(end)) throw TestFailure('still planning');
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('jplan-suggest'))).onPressed, isNotNull);
    await show(find.byKey(const Key('jplan-way-0')));
    // In the simulator's language; «direct» or «via …», as the server's
    // first way goes.
    final t = AppLocalizations.of(tester.element(find.byKey(const Key('jplan-panel'))));
    expect(find.textContaining(t.jplanWay(1)), findsWidgets);

    // The second way.
    await show(find.byKey(const Key('jplan-way-1')));
    await tester.tap(find.byKey(const Key('jplan-way-1')));
    await tester.pump(const Duration(seconds: 1));
    await show(find.byKey(const Key('jplan-stage-0')));
    // Above the first day: in the smaller panel of Planen, scrolled up to.
    await tester.scrollUntilVisible(find.byKey(const Key('jplan-summary')), -200, scrollable: panel);
    expect(find.byKey(const Key('jplan-summary')), findsOneWidget);

    // Where it shares a night with another way, go on along that one. The
    // days are built as they scroll into view.
    final switchButtons = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('jplan-switch-'),
    );
    for (var i = 0; i < 40 && switchButtons.evaluate().isEmpty; i++) {
      await tester.drag(panel, const Offset(0, -120));
      await tester.pump(const Duration(milliseconds: 300));
    }
    if (switchButtons.evaluate().isNotEmpty) {
      await tester.ensureVisible(switchButtons.first);
      await tester.pump(const Duration(milliseconds: 300));
      final to = int.parse((switchButtons.evaluate().first.widget.key! as ValueKey<String>).value.split('-').last);
      await tester.tap(switchButtons.first);
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining(t.jplanWay(to + 1)), findsWidgets);
    } else {
      debugPrint('no shared night between the ways');
    }

    await show(find.byKey(const Key('jplan-title')));
    expect(tester.widget<TextField>(find.byKey(const Key('jplan-title'))).controller!.text, isNotEmpty);
    await tester.enterText(find.byKey(const Key('jplan-title')), title);
    // As a user does: a tap outside closes the number pad over the buttons.
    await tester.tapAt(tester.getTopLeft(find.byKey(const Key('jplan-panel'))) + const Offset(4, 4));
    await tester.pump(const Duration(milliseconds: 500));
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
