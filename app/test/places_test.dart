import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/l10n/app_localizations_de.dart';
import 'package:alvyo/place_layer.dart';
import 'package:alvyo/place_search.dart';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('de'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  test('huts from zoom 8, hotels and campsites from 10', () {
    const both = {PlaceGroup.huts, PlaceGroup.lodging};
    expect(placeKinds({}, 12), isEmpty);
    expect(placeKinds(both, 7), isEmpty);
    expect(placeKinds(both, 9), ['hut']);
    expect(placeKinds(both, 10), ['hut', 'hotel', 'campsite']);
    expect(placeKinds({PlaceGroup.lodging}, 12), ['hotel', 'campsite']);
  });

  test('along the way from zoom 12, only the kinds switched on', () {
    expect(placeKinds({PlaceGroup.pois}, 11), isEmpty);
    expect(placeKinds({PlaceGroup.pois}, 12), hasLength(10));
    expect(placeKinds({PlaceGroup.pois, PlaceGroup.huts}, 12, {'water', 'firepit'}), ['hut', 'water', 'firepit']);
  });

  test('base map, overlays and kinds along the way are remembered', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final s = PlaceSettings();
    await s.loaded;
    expect(s.base.value, 'landeskarte');
    expect(s.overlays.value, {'wanderwege'});
    expect(s.pois.value, hasLength(10));
    await s.setBase('luftbild');
    await s.toggleOverlay('wanderwege');
    await s.toggleOverlay('hangneigung');
    await s.togglePoi('restaurant');
    final again = PlaceSettings();
    await again.loaded;
    expect(again.base.value, 'luftbild');
    expect(again.overlays.value, {'hangneigung'});
    expect(again.pois.value, isNot(contains('restaurant')));
    expect(again.pois.value, contains('firepit'));
  });

  test('websites are links only when http(s)', () {
    expect(webLink('https://www.sac-cas.ch'), 'https://www.sac-cas.ch');
    expect(webLink(' http://huette.ch/x '), 'http://huette.ch/x');
    expect(webLink('javascript:alert(1)'), isNull);
    expect(webLink('www.huette.ch'), isNull);
    expect(webLink(''), isNull);
  });

  test('kinds of places in words', () {
    final t = AppLocalizationsDe();
    expect(placeKindText(t, 'hut', 'alpine_hut'), 'Hütte');
    expect(placeKindText(t, 'hut', 'wilderness_hut'), 'Unbewartete Hütte');
    expect(placeKindText(t, 'pt_stop', 'Zug, Bus'), 'Zug, Bus');
    expect(placeKindText(t, 'pt_stop', ''), 'ÖV-Haltestelle');
    expect(placeKindText(t, 'name', 'Hauptgipfel, Isenthal (UR)'), 'Hauptgipfel, Isenthal (UR)');
  });

  test('the switched on places are remembered', () async {
    FlutterSecureStorage.setMockInitialValues({'map-places': 'huts'});
    final s = PlaceSettings();
    await s.loaded;
    expect(s.shown.value, {PlaceGroup.huts});
    await s.toggle(PlaceGroup.lodging);
    await s.toggle(PlaceGroup.huts);
    final again = PlaceSettings();
    await again.loaded;
    expect(again.shown.value, {PlaceGroup.lodging});
  });

  testWidgets('the layer menu switches places on and off', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final s = PlaceSettings();
    await tester.pumpWidget(_app(Center(child: PlaceLayerButton(settings: s))));
    await tester.tap(find.byKey(const Key('map-layers')));
    await tester.pumpAndSettle();

    // The base map and an overlay.
    await tester.tap(find.text('Luftbild'));
    await tester.pumpAndSettle();
    expect(s.base.value, 'luftbild');
    await tester.scrollUntilVisible(find.byKey(const Key('map-overlay-jagdbanngebiete')), 100);
    await tester.tap(find.byKey(const Key('map-overlay-wildruhezonen')));
    await tester.pumpAndSettle();
    expect(s.overlays.value, {'wanderwege', 'wildruhezonen'});

    await tester.scrollUntilVisible(find.byKey(const Key('map-layer-lodging')), 100);
    await tester.tap(find.byKey(const Key('map-layer-huts')));
    await tester.pumpAndSettle();
    expect(s.shown.value, {PlaceGroup.huts});
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('map-layer-huts'))).value, isTrue);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('map-layer-lodging'))).value, isFalse);

    // Along the way: the kinds only once it is on.
    expect(find.byKey(const Key('map-poi-firepit')), findsNothing);
    await tester.scrollUntilVisible(find.byKey(const Key('map-layer-pois')), 100);
    await tester.tap(find.byKey(const Key('map-layer-pois')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('map-poi-firepit')), 100);
    expect(find.text('Feuerstelle'), findsOneWidget);
    await tester.tap(find.byKey(const Key('map-poi-firepit')));
    await tester.pumpAndSettle();
    expect(s.pois.value, isNot(contains('firepit')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tapped place: name, kind and the website to copy', (tester) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showPlace(
              context,
              Pin.fromJson({
                'id': 'p1',
                'kind': 'hut',
                'name': 'Glecksteinhütte',
                'detail': 'alpine_hut',
                'lon': 8.1,
                'lat': 46.6,
                'website': 'https://gleckstein.ch',
              }),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Glecksteinhütte'), findsOneWidget);
    expect(find.text('Hütte'), findsOneWidget);
    expect(find.text('Website: https://gleckstein.ch'), findsOneWidget);
  });

  testWidgets('the search waits for the typing to stop and shows only the latest answer', (tester) async {
    final asked = <String>[];
    final answers = <String, Completer<http.Response>>{};
    final api = Api(
      'https://alvyo.test',
      client: MockClient((req) {
        final q = req.url.queryParameters['q']!;
        asked.add(q);
        return (answers[q] = Completer()).future;
      }),
    );
    http.Response found(String name) => http.Response(
      jsonEncode({
        'places': [
          {
            'name': name,
            'kind': 'hut',
            'detail': 'alpine_hut',
            'at': [8.1, 46.6],
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    FoundPlace? picked;
    await tester.pumpWidget(_app(PlaceSearch(api: api, onPick: (p) => picked = p)));
    await tester.tap(find.byKey(const Key('place-search-open')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('place-search')), 'Gl');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const Key('place-search')), 'Gle');
    await tester.pump(const Duration(milliseconds: 300));
    expect(asked, ['Gle'], reason: 'typed quickly: one search');

    await tester.enterText(find.byKey(const Key('place-search')), 'Glec');
    await tester.pump(const Duration(milliseconds: 300));
    expect(asked, ['Gle', 'Glec']);
    answers['Glec']!.complete(found('Glecksteinhütte'));
    await tester.pump();
    answers['Gle']!.complete(found('Gletscherstube')); // late: dropped
    await tester.pump();
    expect(find.text('Glecksteinhütte'), findsOneWidget);
    expect(find.text('Gletscherstube'), findsNothing);

    await tester.tap(find.byKey(const Key('place-result-0')));
    await tester.pump();
    expect(picked!.name, 'Glecksteinhütte');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('place-search')), findsNothing, reason: 'the search page closed');
    expect(find.byKey(const Key('place-result-0')), findsNothing);
  });

  // In a planner's panel the results would come below the field, under the
  // keyboard: the search opens a page of its own, the results at the top.
  testWidgets('a search low in a small panel opens a page with the results at the top', (tester) async {
    final api = Api(
      'https://alvyo.test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'places': [
              {
                'name': 'Weisstannen',
                'kind': 'pt_stop',
                'detail': 'Bus',
                'at': [9.33, 46.99],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    FoundPlace? picked;
    await tester.pumpWidget(
      _app(
        SizedBox(
          height: 200,
          child: ListView(
            children: [
              const SizedBox(height: 150), // the points and settings above
              PlaceSearch(api: api, onPick: (p) => picked = p),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('place-search-open')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('place-search')), 'Weiss');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('place-result-0'))).top, lessThan(200));
    await tester.tap(find.byKey(const Key('place-result-0')));
    await tester.pumpAndSettle();
    expect(picked?.name, 'Weisstannen');
  });
}
