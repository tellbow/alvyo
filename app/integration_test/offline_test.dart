import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/main.dart';
import 'package:alvyo/offline/packs.dart';
import 'package:alvyo/session.dart';

/// A login whose server cannot be reached, as in the mountains.
class OfflineSession extends Session {
  @override
  Future<Api?> restore() async => Api('http://127.0.0.1:9', token: 'offline');
}

/// Against a local dev server (web dev server on :5173 with the demo account
/// appdemo / sehr-geheim-123 and imported routes):
///   `flutter test integration_test -d SIMULATOR_ID`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(WidgetTester tester, Finder f, {Duration timeout = const Duration(seconds: 60)}) async {
    final end = DateTime.now().add(timeout);
    while (f.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $f');
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('log in, save a route offline, then open it without a connection', (tester) async {
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

    final saved = find.byKey(const Key('offline-remove'));
    final save = find.byKey(const Key('offline-save'));
    await waitFor(
      tester,
      find.byWidgetPredicate((w) => w.key == const Key('offline-save') || w.key == const Key('offline-remove')),
    );
    if (saved.evaluate().isNotEmpty) {
      await tester.tap(saved); // from an earlier run: start over
      await waitFor(tester, save);
    }
    final started = DateTime.now();
    await tester.tap(save);
    await waitFor(tester, saved, timeout: const Duration(minutes: 5));
    debugPrint('offline save took ${DateTime.now().difference(started).inSeconds} s');

    // The route and both layers are on the phone; the map now shows them.
    final store = await PackStore.open();
    final route = (await store.savedRoutes()).singleWhere((r) => r.title == 'Sargans–Weisstannen');
    final pack = (await store.saved(route.id))!;
    expect(pack.files.keys, unorderedEquals(['landeskarte', 'wanderwege']));
    // Kept out of iCloud backups (the native side answers with the flag).
    expect(await const MethodChannel('alvyo/backup').invokeMethod<bool>('exclude', store.root.path), isTrue);
    for (final f in pack.files.values) {
      debugPrint('${f.split('/').last}: ${File(f).lengthSync()} bytes');
    }

    // Without a connection: the saved routes, and the route on its offline map.
    await tester.pumpWidget(AlvyoApp(key: UniqueKey(), session: OfflineSession()));
    await waitFor(tester, find.byKey(const Key('routes-offline')));
    await tester.tap(find.text('Sargans–Weisstannen'));
    await waitFor(tester, saved);
    await tester.pump(const Duration(seconds: 8)); // for a screenshot
  });
}
