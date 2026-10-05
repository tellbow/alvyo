import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/main.dart';

/// Against a local dev server with the demo account (see README.md): a
/// friend's invite link opened in the app, the friend found by the search;
/// a route marked as hiked, on «Übersicht» with its trail conditions, then
/// on one's map with «Hiked». Everything changed is put back.
///   `flutter test integration_test/friends_test.dart -d SIMULATOR_ID`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const server = 'http://localhost:5173';

  Future<void> waitFor(WidgetTester tester, Finder f, {Duration timeout = const Duration(seconds: 60)}) async {
    final end = DateTime.now().add(timeout);
    while (f.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $f');
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> settle(WidgetTester tester) => tester.pump(const Duration(seconds: 1));

  // Once: the server limits logins.
  Future<Api>? session;
  Future<Api> login() => session ??= () async {
    final api = Api(server);
    await api.login('appdemo', 'sehr-geheim-123');
    return api;
  }();

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(AlvyoApp(key: UniqueKey()));
    await settle(tester);
    if (find.byKey(const Key('server')).evaluate().isNotEmpty) {
      await tester.enterText(find.byKey(const Key('server')), server);
      await tester.enterText(find.byKey(const Key('login')), 'appdemo');
      await tester.enterText(find.byKey(const Key('password')), 'sehr-geheim-123');
      await tester.tap(find.byKey(const Key('submit')));
    }
    await waitFor(tester, find.byKey(const Key('tab-profile')));
  }

  testWidgets('a friend\'s invite link opens in the app; the friend is found', (tester) async {
    final me = await login();
    // Someone new, with a public profile, to be friends with.
    final name = 'beat${DateTime.now().millisecondsSinceEpoch % 1000000000}';
    const password = 'sehr-geheim-456';
    final signup = await http.post(
      Uri.parse('$server/api/v1/auth/signup'),
      headers: {'Content-Type': 'application/json', 'Origin': server},
      body: jsonEncode({
        'email': '$name@example.com',
        'username': name,
        'display_name': 'Beat Test',
        'password': password,
        'locale': 'de',
      }),
    );
    expect(signup.statusCode, 201, reason: signup.body);
    final beat = Api(server);
    await beat.login(name, password);
    try {
      final token = await beat.friendLink();

      await start(tester);
      // As iOS hands over alvyo://open/friends/invite/{token}.
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation',
        const JSONMethodCodec().encodeMethodCall(
          MethodCall('pushRouteInformation', {'location': '/friends/invite/$token', 'state': null}),
        ),
        (_) {},
      );
      await waitFor(tester, find.byKey(const Key('friend-invite-accept')));
      await settle(tester);
      expect(find.text('Beat Test invites you'), findsOneWidget);
      await tester.tap(find.byKey(const Key('friend-invite-accept')));
      await waitFor(tester, find.byKey(const Key('friend-invite-done')));
      expect([for (final f in (await me.friends()).friends) f.username], contains(name));

      // The friend, found by the search, as a friend.
      await tester.pageBack();
      await settle(tester);
      await tester.tap(find.byKey(const Key('tab-profile')));
      await settle(tester);
      await tester.scrollUntilVisible(find.byKey(const Key('friends')), 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.byKey(const Key('friends')));
      await waitFor(tester, find.byKey(const Key('friends-search')));
      await tester.enterText(find.byKey(const Key('friends-search')), name);
      await waitFor(tester, find.byKey(Key('friend-of-$name-friends')));
    } finally {
      await beat.deleteMe(password: password);
    }
  });

  testWidgets('a route hiked: marked, its trail conditions, on my map', (tester) async {
    final api = await login();
    final route = (await api.routes()).firstWhere((r) => r.title == 'Sargans–Weisstannen');
    try {
      await api.setDone(route.id, journey: false, on: false);
    } on ApiException {
      // not marked
    }

    await start(tester);
    await waitFor(tester, find.text('Sargans–Weisstannen'));
    await settle(tester);
    await tester.tap(find.text('Sargans–Weisstannen'));
    await waitFor(tester, find.byKey(const Key('item-menu')));
    await settle(tester);
    try {
      await tester.tap(find.byKey(const Key('item-menu')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('item-done')));
      await settle(tester);
      await tester.tap(find.text('OK')); // today
      await waitFor(tester, find.byKey(const Key('done-on')));
      expect((await api.myMap((west: 9.2, south: 46.9, east: 9.6, north: 47.1), done: 'done')).items, isNotEmpty);

      // «Übersicht»: the trail conditions, the photos counted on their tab.
      await tester.scrollUntilVisible(
        find.byKey(const Key('trail-conditions')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.textContaining('Photos '), findsWidgets);

      // «Along the way»: a line tapped shows its point on the map.
      await tester.tap(find.byKey(const Key('tab-along')));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('poi-0')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('poi-0')));
      await settle(tester);

      // My map, hiked only: the route is there.
      await tester.pageBack();
      await settle(tester);
      await tester.tap(find.byKey(const Key('tab-profile')));
      await settle(tester);
      await tester.scrollUntilVisible(find.byKey(const Key('my-map')), 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.byKey(const Key('my-map')));
      await waitFor(tester, find.byKey(const Key('discover-done')));
      await tester.ensureVisible(find.byKey(const Key('discover-done')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('discover-done')));
      await settle(tester);
      await tester.tap(find.text('Hiked').last);
      await waitFor(tester, find.text('Sargans–Weisstannen'));
    } finally {
      await api.setDone(route.id, journey: false, on: false);
    }
  });
}
