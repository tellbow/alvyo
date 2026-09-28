import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:alvyo/main.dart';
import 'package:alvyo/session.dart';

/// The real GPS path, against the local dev server (see offline_test.dart).
/// The simulator must be granted location access and be moving along
/// «Sargans–Weisstannen» (`xcrun simctl privacy … grant location …`,
/// `xcrun simctl location … start …`): opens the route, starts the hike,
/// waits for progress, finishes; the hike is uploaded and listed, then
/// deleted again.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(WidgetTester tester, Finder f, {Duration timeout = const Duration(seconds: 90)}) async {
    final end = DateTime.now().add(timeout);
    while (f.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $f');
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('start a hike with the GPS', (tester) async {
    await tester.pumpWidget(const AlvyoApp());
    await tester.pump(const Duration(seconds: 1));
    if (find.byKey(const Key('server')).evaluate().isNotEmpty) {
      await tester.enterText(find.byKey(const Key('server')), 'http://localhost:5173');
      await tester.enterText(find.byKey(const Key('login')), 'appdemo');
      await tester.enterText(find.byKey(const Key('password')), 'sehr-geheim-123');
      await tester.tap(find.byKey(const Key('submit')));
    }
    await waitFor(tester, find.text('Sargans–Weisstannen'));
    await tester.tap(find.text('Sargans–Weisstannen'));
    await waitFor(tester, find.byKey(const Key('nav-start')));
    await tester.tap(find.byKey(const Key('nav-start')));
    // With contacts (live_test.dart adds one), the hike can be shared first.
    final skip = find.byKey(const Key('live-skip'));
    await waitFor(
      tester,
      find.byWidgetPredicate((w) => w.key == const Key('live-skip') || w.key == const Key('nav-finish')),
    );
    if (skip.evaluate().isNotEmpty) {
      await tester.pump(const Duration(seconds: 1)); // the sheet slides in
      await tester.tap(skip);
    }

    await waitFor(tester, find.byKey(const Key('nav-progress')));
    await tester.pump(const Duration(seconds: 10)); // moving on; for screenshots
    await tester.tap(find.byKey(const Key('nav-finish')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-finish-confirm')));
    await waitFor(tester, find.byKey(const Key('nav-saved')));
    final saved = (find.byKey(const Key('nav-saved')).evaluate().first.widget as Text).data!;
    debugPrint('saved: $saved');
    expect(saved, matches(RegExp('Meine Routen|My routes')), reason: 'uploaded right away');

    // Back in the list, the hike is there (once the hike screen is gone).
    await waitFor(tester, find.byType(BackButton).hitTestable());
    while (find.byType(BackButton).evaluate().length > 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pageBack();
    final hiked = find.textContaining(RegExp('Gewandert am|Hiked on'));
    await waitFor(tester, hiked);

    // Clean up the demo account.
    final api = (await Session().restore())!;
    for (final r in await api.routes()) {
      if (r.hikedAt != null && r.title.startsWith('Sargans–Weisstannen, ')) {
        final res = await http.delete(
          Uri.parse('${api.server}/api/v1/routes/${r.id}'),
          headers: {'Authorization': 'Bearer ${api.token}'},
        );
        expect(res.statusCode, 204);
      }
    }
  });
}
