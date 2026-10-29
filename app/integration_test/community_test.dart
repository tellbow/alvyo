import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/main.dart';
import 'package:alvyo/settings.dart';

import 'login.dart';

/// Against a local dev server with the demo account (see README.md): the
/// profile's settings, a route's description, likes and comments, a
/// collection, a stage's accommodation, sharing and the feed, as on the
/// website. Everything changed is put back.
///   `flutter test integration_test/community_test.dart -d SIMULATOR_ID`
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

  /// Closes the keyboard, which covers the bottom of a sheet, and taps [key].
  Future<void> tapBelowKeyboard(WidgetTester tester, Key key) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await tester.ensureVisible(find.byKey(key));
    await settle(tester);
    await tester.tap(find.byKey(key));
  }

  // Once: the server limits logins.
  Future<Api>? session;
  Future<Api> login() => session ??= () async {
    final api = Api('http://localhost:5173');
    await api.login('appdemo', 'sehr-geheim-123');
    return api;
  }();

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(AlvyoApp(key: UniqueKey()));
    await settle(tester);
    await logInIfAsked(tester);
    await waitFor(tester, find.byKey(const Key('tab-profile')));
  }

  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).last);
    await settle(tester);
  }

  testWidgets('the profile: dark, a language of one\'s own, back to the phone\'s', (tester) async {
    await start(tester);
    await tester.tap(find.byKey(const Key('tab-profile')));
    await waitFor(tester, find.byKey(const Key('theme')));
    await tester.tap(find.byKey(const Key('theme'))); // a sheet with the choices
    await settle(tester);
    await tester.tap(find.text('Dark')); // the simulator is in English
    await settle(tester);
    expect(Theme.of(tester.element(find.byKey(const Key('theme')))).brightness, Brightness.dark);
    expect(AppSettings.instance.theme.value, ThemeMode.dark);

    await tester.tap(find.byKey(const Key('language')));
    await settle(tester);
    await tester.tap(find.text('Italiano').last);
    await settle(tester);
    expect(find.text('IMPOSTAZIONI'), findsOneWidget); // the settings' heading
    final api = await login();
    expect((await api.me()).locale, 'it', reason: 'e-mails in Italian too');

    // Back to the phone's: light or dark and the language of the simulator.
    await tester.tap(find.byKey(const Key('theme')));
    await settle(tester);
    await tester.tap(find.text('Automatico').last);
    await settle(tester);
    await tester.tap(find.byKey(const Key('language')));
    await settle(tester);
    await tester.tap(find.text('Automatico').last);
    await settle(tester);
    expect(AppSettings.instance.theme.value, ThemeMode.system);
    expect(AppSettings.instance.locale.value, isNull);
    await api.updateMe(locale: 'de');
  });

  testWidgets('a route: description, a like and a comment; into a new collection', (tester) async {
    final api = await login();
    final route = (await api.routes()).firstWhere((r) => r.title == 'Sargans–Weisstannen');
    final before = await api.route(route.id);
    final note = 'Test ${DateTime.now().millisecondsSinceEpoch}';

    await start(tester);
    await waitFor(tester, find.byKey(const Key('tab-tours')));
    await tester.tap(find.byKey(const Key('tab-tours')));
    await waitFor(tester, find.text('Sargans–Weisstannen'));
    await settle(tester);
    await tapAboveBar(tester, find.text('Sargans–Weisstannen'));
    await waitFor(tester, find.byKey(const Key('item-menu')));
    await settle(tester);

    await tester.tap(find.byKey(const Key('item-menu')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('item-edit')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('edit-description')), note);
    await tapBelowKeyboard(tester, const Key('edit-save'));
    await waitFor(
      tester,
      find.byWidgetPredicate((w) => w.key == const Key('route-description') && w is Text && w.data == note),
    );
    expect((await api.route(route.id)).description, note);

    // Likes and comments in their tab.
    await tester.tap(find.byKey(const Key('tab-comments')));
    await settle(tester);
    await scrollTo(tester, find.byKey(const Key('like')));
    final likes = (await api.social(route.id)).likes;
    final liked = (await api.social(route.id)).liked;
    await tester.tap(find.byKey(const Key('like')));
    await waitFor(tester, find.byWidgetPredicate((w) => w is IconButton && w.isSelected == !liked));
    expect((await api.social(route.id)).likes, liked ? likes - 1 : likes + 1);

    await scrollTo(tester, find.byKey(const Key('comment-write')));
    await tester.tap(find.byKey(const Key('comment-write')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('comment-dialog-text')), note);
    await tester.tap(find.byKey(const Key('comment-dialog-ok')));
    // The comment, once the dialog has gone (the description is on «Übersicht»).
    final shown = find.byWidgetPredicate((w) => w is Text && w.data == note);
    for (var i = 0; i < 120 && shown.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(shown, findsOneWidget);
    final comment = (await api.social(route.id)).comments.lastWhere((c) => c.body == note);

    await tester.tap(find.byKey(const Key('item-menu')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('item-collection')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('pick-new')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('ask-text')), note);
    await tester.tap(find.byKey(const Key('ask-text-ok')));
    await settle(tester);
    await settle(tester);
    final collection = (await api.collections()).firstWhere((c) => c.title == note);
    expect(collection.items, 1);

    // Put back.
    final after = await api.social(route.id);
    expect(after.comments.where((c) => c.body == note), hasLength(1), reason: 'posted once');
    expect(after.liked, !liked);
    await api.deleteComment(route.id, comment.id);
    final back = await api.like(route.id, liked);
    expect(back.liked, liked);
    expect(back.comments.where((c) => c.body == note), isEmpty);
    await api.deleteCollection(collection.id);
    await api.updateRoute(route.id, (await api.route(route.id)).version, {'description': before.description});
  });

  testWidgets('a stage\'s accommodation; the journey\'s sharing refuses an unknown name', (tester) async {
    final api = await login();
    final id = (await api.journeys()).firstWhere((j) => j.title == 'Via Alpina').id;
    final stage = (await api.journey(id)).stages.first;
    final hut = 'Hütte ${DateTime.now().millisecondsSinceEpoch}';

    await start(tester);
    await tester.tap(find.byKey(const Key('tab-tours')));
    await waitFor(tester, find.text('Via Alpina'));
    await settle(tester);
    await tapAboveBar(tester, find.text('Via Alpina'));
    await waitFor(tester, find.byKey(const Key('stage-more-0')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('stage-more-0')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('stage-edit')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('stage-accommodation')), hut);
    await tapBelowKeyboard(tester, const Key('stage-save'));
    await waitFor(tester, find.textContaining(hut).hitTestable());
    await settle(tester);
    expect((await api.journey(id)).stages.first.accommodation, hut);

    await tester.tap(find.byKey(const Key('item-menu')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('item-share')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('share-who')), 'niemand-${DateTime.now().millisecondsSinceEpoch}');
    await tester.tap(find.byKey(const Key('share-invite')));
    await settle(tester);
    await settle(tester);
    expect(await api.grants(id, journey: true), isEmpty);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.style?.color == Theme.of(tester.element(find.byKey(const Key('share-who')))).colorScheme.error,
      ),
      findsOneWidget,
      reason: 'there is no such user',
    );

    await api.updateStage(id, (await api.journey(id)).stages.first, {'accommodation': stage.accommodation});
  });

  testWidgets('the feed and the map of one\'s tours open', (tester) async {
    await start(tester);
    // The feed on Entdecken; «Alle» for all of it.
    await tester.tap(find.byKey(const Key('tab-discover')));
    await waitFor(tester, find.byKey(const Key('feed-all')));
    await tester.tap(find.byKey(const Key('feed-all')));
    await waitFor(tester, find.byType(RefreshIndicator));
    await settle(tester);
    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.byKey(const Key('tab-tours')));
    await waitFor(tester, find.byKey(const Key('tours-map')));
    await tester.tap(find.byKey(const Key('tours-map')));
    await waitFor(tester, find.byKey(const Key('discover-item-0')), timeout: const Duration(seconds: 30));
  });
}

/// Taps [f] in a list that runs under the floating bar: scrolled only when
/// it is not clear of the bar (a short list scrolled anyway bounces back).
Future<void> tapAboveBar(WidgetTester tester, Finder f) async {
  final view = tester.view;
  final clear = view.physicalSize.height / view.devicePixelRatio - 160;
  if (tester.getCenter(f).dy > clear) {
    final list = find.ancestor(of: f, matching: find.byType(Scrollable)).first;
    await tester.ensureVisible(f);
    await tester.pump(const Duration(seconds: 1));
    final y = tester.getCenter(f).dy;
    if (y > clear) await tester.drag(list, Offset(0, clear - y));
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.tap(f);
}
