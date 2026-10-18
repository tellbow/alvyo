import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/main.dart';

import 'login.dart';

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
    await logInIfAsked(tester);
    await waitFor(tester, find.byKey(const Key('tab-plan')));
    await tester.tap(find.byKey(const Key('tab-plan'))); // Tagestour first
    await waitFor(tester, find.byKey(const Key('place-search-open')));

    for (final q in ['Sargans', 'Weisstannen']) {
      await tester.tap(find.byKey(const Key('place-search-open')));
      await waitFor(tester, find.byKey(const Key('place-search')));
      await tester.enterText(find.byKey(const Key('place-search')), q);
      await waitFor(tester, find.byKey(const Key('place-result-0')));
      await tester.tap(find.byKey(const Key('place-result-0')));
      await tester.pump(const Duration(seconds: 1)); // the search page closes
    }
    await waitFor(tester, find.byKey(const Key('planner-point-1')));
    // Legs take a moment; the save button is there once both points are.
    final save = find.byKey(const Key('planner-save'));
    final panel = find.descendant(of: find.byKey(const Key('planner-panel')), matching: find.byType(Scrollable)).first;
    final end = DateTime.now().add(const Duration(seconds: 60));
    while (true) {
      // The panel grows as the legs come: the button may move out of view.
      await tester.scrollUntilVisible(save, 200, scrollable: panel);
      if (tester.widget<FilledButton>(save).onPressed != null) break;
      if (DateTime.now().isAfter(end)) throw TestFailure('the leg was not computed');
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pump(const Duration(seconds: 2)); // for a screenshot

    await tester.tap(save);
    await waitFor(tester, find.byKey(const Key('planner-title')));
    final title = 'Geplant ${DateTime.now().millisecondsSinceEpoch}';
    await tester.enterText(find.byKey(const Key('planner-title')), title);
    await tester.tap(find.byKey(const Key('planner-save-confirm')));

    // The saved route opens, ready to keep offline and to hike.
    await waitFor(tester, find.byKey(const Key('nav-start')));
    expect(find.text(title), findsOneWidget);
    // The planner has left and the route's map is set up (MapLibre cannot be
    // disposed before its view exists).
    await tester.pump(const Duration(seconds: 3));
    await tester.pageBack();
    await waitFor(tester, find.text(title));

    // Not kept in the demo account: other tests look for its routes in the
    // list.
    final api = Api('http://localhost:5173');
    await api.login('appdemo', 'sehr-geheim-123');
    final id = (await api.routes()).firstWhere((r) => r.title == title).id;
    final deleted = await http.delete(
      Uri.parse('http://localhost:5173/api/v1/routes/$id'),
      headers: {'Authorization': 'Bearer ${api.token}'},
    );
    expect(deleted.statusCode, lessThan(300));
  });

  testWidgets('the line and a point dragged on the map; the bug report\'s screenshot shows the map', (tester) async {
    await tester.pumpWidget(const AlvyoApp());
    await tester.pump(const Duration(seconds: 1));
    await logInIfAsked(tester);
    await waitFor(tester, find.byKey(const Key('tab-plan')));
    await tester.tap(find.byKey(const Key('tab-plan')));
    await waitFor(tester, find.byKey(const Key('place-search-open')));
    // Close together: the camera goes to the last place found, and the whole
    // leg is in view.
    for (final q in ['Weisstannen', 'Vorsiez']) {
      await tester.tap(find.byKey(const Key('place-search-open')));
      await waitFor(tester, find.byKey(const Key('place-search')));
      await tester.enterText(find.byKey(const Key('place-search')), q);
      await waitFor(tester, find.byKey(const Key('place-result-0')));
      await tester.tap(find.byKey(const Key('place-result-0')));
      await tester.pump(const Duration(seconds: 1));
    }
    String name(int i) => (tester.widget<ListTile>(find.byKey(Key('planner-point-$i'))).title as Text).data!;
    await waitFor(tester, find.byKey(const Key('planner-leg-handle-0')));
    expect(name(1), 'Vorsiez');
    await tester.pump(const Duration(seconds: 3)); // the camera goes to both points

    // The line dragged off it: no other way between these two (the dev
    // graph has one), so a stop where it was let go.
    await tester.timedDrag(
      find.byKey(const Key('planner-leg-handle-0')),
      const Offset(-50, 30),
      const Duration(milliseconds: 800),
    );
    await waitFor(tester, find.byKey(const Key('planner-point-2')));
    expect(name(2), 'Vorsiez');

    // Feedback issue 12: a point dragged like on the website; no longer the
    // place.
    await waitFor(tester, find.byKey(const Key('planner-handle-2')));
    // A quarter of the way back to the start: still in the valley, on paths.
    final back =
        (tester.getCenter(find.byKey(const Key('planner-handle-0'))) -
            tester.getCenter(find.byKey(const Key('planner-handle-2')))) /
        4;
    await tester.timedDrag(find.byKey(const Key('planner-handle-2')), back, const Duration(milliseconds: 800));
    await tester.pump(const Duration(seconds: 1));
    expect(name(2), isNot('Vorsiez'));
    // Its legs computed again (on a path or not: the map's zoom decides).
    final computing = find.descendant(
      of: find.byKey(const Key('planner-panel')),
      matching: find.byType(LinearProgressIndicator),
    );
    final end = DateTime.now().add(const Duration(seconds: 60));
    while (computing.evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(end)) throw TestFailure('the legs were not computed again');
      await tester.pump(const Duration(milliseconds: 250));
    }

    // The native screenshot has the map (Flutter's own left it one colour):
    // many colours in the middle of the map.
    await tester.pump(const Duration(seconds: 2));
    final png = await const MethodChannel('alvyo/screenshot').invokeMethod<Uint8List>('window');
    expect(png, isNotNull);
    final image = (await (await ui.instantiateImageCodec(png!)).getNextFrame()).image;
    final pixels = (await image.toByteData())!;
    final colours = <int>{};
    for (var y = image.height * 0.3; y < image.height * 0.5; y += 7) {
      for (var x = image.width * 0.2; x < image.width * 0.8; x += 7) {
        colours.add(pixels.getUint32((y.toInt() * image.width + x.toInt()) * 4));
      }
    }
    expect(colours.length, greaterThan(50), reason: 'the map area looks empty');
  });
}
