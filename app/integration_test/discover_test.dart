import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/main.dart';

/// Against a local dev server (web dev server on :5173 with the demo account
/// appdemo / sehr-geheim-123 and imported routes, GraphHopper running):
/// makes a public route from the start of the first imported one unless
/// there is one, finds it under «Entdecken», and opens it.
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
    const switzerland = (west: 5.9, south: 45.8, east: 10.5, north: 47.8);
    final found = await api.discover(switzerland, kind: 'route');
    if (!found.items.any((it) => it.title == title)) {
      final line = (await api.route((await api.routes()).first.id)).line;
      final from = (lon: line.first[0], lat: line.first[1]);
      final to = (lon: line[line.length ~/ 5][0], lat: line[line.length ~/ 5][1]);
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
    await waitFor(tester, find.byKey(const Key('discover')));
    await tester.tap(find.byKey(const Key('discover')));

    // Routes only, so the test route is among the first shown.
    await waitFor(tester, find.byKey(const Key('discover-kind')));
    await tester.tap(find.byKey(const Key('discover-kind')));
    await waitFor(tester, find.byKey(const Key('discover-kind-route')));
    await tester.pump(const Duration(milliseconds: 500)); // the menu opens
    await tester.tap(find.byKey(const Key('discover-kind-route')).last);
    await waitFor(tester, find.text(title));
    await tester.pump(const Duration(seconds: 3)); // for a screenshot: the lines on the map

    await tester.tap(find.text(title));
    await waitFor(tester, find.byKey(const Key('nav-start')));
    expect(find.byKey(const Key('offline-save')), findsOneWidget);
  });
}
