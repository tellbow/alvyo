import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/main.dart';

/// Against a local dev server (web dev server on :5173 with the demo account
/// appdemo / sehr-geheim-123 and imported routes, GraphHopper running):
/// makes a public route near the centre of Switzerland unless there is one,
/// finds it under «Entdecken», and opens it. The screen starts with the
/// whole country and lists the 50 nearest its centre: other public routes
/// of the dev database (the web's end-to-end tests make many in the Bernese
/// Oberland) are further away.
///   `flutter test integration_test/discover_test.dart -d SIMULATOR_ID`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(WidgetTester tester, Finder f, {Duration timeout = const Duration(seconds: 60)}) async {
    final end = DateTime.now().add(timeout);
    while (f.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $f');
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('discover: a public route on the map and in the list, opened', (tester) async {
    const title = 'Entdecken-Test';
    final api = Api('http://localhost:5173');
    await api.login('appdemo', 'sehr-geheim-123');
    // By the Sarnersee, near the centre of the map's first view.
    const from = (lon: 8.2460, lat: 46.8440), to = (lon: 8.2600, lat: 46.8520);
    const around = (west: 8.2, south: 46.8, east: 8.3, north: 46.9);
    final found = await api.discover(around, kind: 'route');
    if (!found.items.any((it) => it.title == title)) {
      await api.createRoute(
        title: title,
        profile: 'hike',
        anchors: [Anchor(from.lon, from.lat), Anchor(to.lon, to.lat)],
        legs: [await api.leg(from, to)],
        visibility: 'public',
      );
    }

    await tester.pumpWidget(const AlvyoApp());
    await tester.pump(const Duration(seconds: 1));
    if (find.byKey(const Key('server')).evaluate().isNotEmpty) {
      await tester.enterText(find.byKey(const Key('server')), 'http://localhost:5173');
      await tester.enterText(find.byKey(const Key('login')), 'appdemo');
      await tester.enterText(find.byKey(const Key('password')), 'sehr-geheim-123');
      await tester.tap(find.byKey(const Key('submit')));
    }
    // Entdecken › In deiner Nähe › Karte.
    await waitFor(tester, find.byKey(const Key('nearby-map')));
    await tester.tap(find.byKey(const Key('nearby-map')));

    // Routes only, so the test route is among the first shown.
    await waitFor(tester, find.byKey(const Key('discover-kind')));
    await tester.tap(find.byKey(const Key('discover-kind')));
    await waitFor(tester, find.byKey(const Key('discover-kind-route')));
    await tester.pump(const Duration(milliseconds: 500)); // the menu opens
    await tester.tap(find.byKey(const Key('discover-kind-route')).last);
    await waitFor(tester, find.byKey(const Key('discover-item-0')));
    final list = find.ancestor(of: find.byKey(const Key('discover-item-0')), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text(title), 200, scrollable: list, maxScrolls: 60);
    await tester.pump(const Duration(seconds: 3)); // for a screenshot: the lines on the map

    await tester.tap(find.text(title));
    await waitFor(tester, find.byKey(const Key('nav-start')));
    expect(find.byKey(const Key('offline-save')), findsOneWidget);
    // The route's map sets up before the test ends: MapLibre cannot be
    // disposed before its view exists.
    await tester.pump(const Duration(seconds: 3));
  });
}
