import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/screens/collection_map_screen.dart';
import 'package:alvyo/screens/collections_screen.dart';

const _collection = '0199a000-0000-7000-8000-00000000000c';
const _route = '0199a000-0000-7000-8000-00000000000a';

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _body({
  required String visibility,
  required String role,
  int hidden = 0,
  List<Object> lines = const [],
}) => {
  'id': _collection,
  'title': 'Mit Freunden',
  'description': '',
  'owner_username': 'wodan',
  'visibility': visibility,
  'role': role,
  'can_edit': role != 'viewer',
  'hidden': hidden,
  'item_list': [
    {
      'id': 'i1',
      'kind': 'route',
      'target_id': _route,
      'title': 'Bachalpsee',
      'owner_username': 'wodan',
      'note': '',
      'distance_m': 6000.0,
      'ascent_m': 300.0,
      'duration_s': 7200,
      'sac_grade': 1,
      'sac_max': 1,
      'stages': 0,
      'lines': lines,
    },
  ],
};

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('de'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void main() {
  late Directory support;
  setUpAll(() {
    support = Directory.systemTemp.createTempSync('support');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => support.path,
    );
  });
  tearDownAll(() => support.deleteSync(recursive: true));

  /// Opens the collection's route as a user with [role] and returns the
  /// share token of the first call for the route.
  Future<String?> openRoute(
    WidgetTester tester, {
    required String visibility,
    required String role,
    String? link,
    int hidden = 0,
  }) async {
    final asked = <Uri>[];
    final api = Api(
      'https://alvyo.test',
      client: MockClient((req) async {
        asked.add(req.url);
        if (req.url.path == '/api/v1/collections/$_collection') {
          return _json(_body(visibility: visibility, role: role, hidden: hidden));
        }
        return http.Response('{"title": "Not Found", "status": 404}', 404);
      }),
    );
    if (link != null) api.shareTokens[_collection] = link;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CollectionScreen(api: api, id: _collection, title: ''),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('collection-hidden')), hidden > 0 ? findsOneWidget : findsNothing);
    await tester.tap(find.text('Bachalpsee'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final call = asked.firstWhere((u) => u.path.startsWith('/api/v1/routes/$_route'), orElse: () => fail('$asked'));
    return call.queryParameters['t'];
  }

  testWidgets('a collection opened by link opens its routes through it', (tester) async {
    expect(
      await openRoute(tester, visibility: 'unlisted', role: 'viewer', link: 'linktoken', hidden: 2),
      'c.$_collection.linktoken',
    );
  });

  testWidgets('a public collection opens its routes through it', (tester) async {
    expect(await openRoute(tester, visibility: 'public', role: 'viewer'), 'c.$_collection');
  });

  testWidgets('invited people need no token', (tester) async {
    expect(await openRoute(tester, visibility: 'private', role: 'viewer'), isNull);
  });

  testWidgets('nor does the owner', (tester) async {
    expect(await openRoute(tester, visibility: 'unlisted', role: 'owner', link: 'linktoken'), isNull);
  });

  testWidgets('removing a tour asks first', (tester) async {
    final deleted = <String>[];
    final api = Api(
      'https://alvyo.test',
      client: MockClient((req) async {
        if (req.method == 'DELETE') deleted.add(req.url.path);
        return _json(_body(visibility: 'private', role: 'editor'));
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CollectionScreen(api: api, id: _collection, title: ''),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-remove-i1')));
    await tester.pumpAndSettle();
    expect(
      find.text('«Bachalpsee» aus der Sammlung entfernen? Die Route oder Etappentour selbst bleibt.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('remove-cancel')));
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);

    await tester.tap(find.byKey(const Key('item-remove-i1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remove-confirm')));
    await tester.pumpAndSettle();
    expect(deleted, ['/api/v1/collections/$_collection/items/i1']);
  });

  testWidgets('a tour is marked as hiked from the list', (tester) async {
    final calls = <String>[];
    final api = Api(
      'https://alvyo.test',
      token: 't',
      client: MockClient((req) async {
        if (req.url.path.endsWith('/done')) {
          calls.add('${req.method} ${req.url.path}');
          return _json({'done_on': '2026-08-01', 'done_marked': true});
        }
        return _json(_body(visibility: 'private', role: 'viewer'));
      }),
    );
    await tester.pumpWidget(_app(CollectionScreen(api: api, id: _collection, title: '')));
    await tester.pumpAndSettle();
    expect(find.text('0 von 1 gewandert'), findsOneWidget);
    await tester.tap(find.byKey(const Key('item-done-i1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('done-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); // the day: today
    await tester.pumpAndSettle();
    expect(calls, ['PUT /api/v1/routes/$_route/done']);
    expect(find.text('1 von 1 gewandert'), findsOneWidget);
  });

  const line = [
    [7.9, 46.6],
    [7.95, 46.65],
  ];

  test('each item keeps its lines, a journey one per stage', () {
    final body = _body(visibility: 'private', role: 'owner');
    final item = (body['item_list'] as List).first as Map<String, dynamic>;
    final c = Collection.fromJson({
      ...body,
      'item_list': [
        {
          ...item,
          'kind': 'journey',
          'lines': [
            line,
            [
              [7.95, 46.65],
              [8.0, 46.7],
              [8.05, 46.7],
            ],
          ],
        },
      ],
    });
    expect([for (final l in c.items.single.lines) l.length], [2, 3]);
    expect(c.items.single.lines[1].last, [8.05, 46.7]);
    expect(Collection.fromJson(body).items.single.lines, isEmpty);
  });

  testWidgets('the map is offered only when an item has a line', (tester) async {
    for (final (lines, shown) in [
      (const <Object>[], findsNothing),
      (const <Object>[line], findsOneWidget),
    ]) {
      final api = Api(
        'https://alvyo.test',
        client: MockClient((req) async => _json(_body(visibility: 'private', role: 'owner', lines: lines))),
      );
      await tester.pumpWidget(_app(CollectionScreen(api: api, id: _collection, title: '')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('collection-map')), shown);
      expect(find.text('Karte der Sammlung'), shown);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('the map lists the items and opens them through the collection', (tester) async {
    final asked = <Uri>[];
    final api = Api(
      'https://alvyo.test',
      client: MockClient((req) async {
        asked.add(req.url);
        return http.Response('{"title": "Not Found", "status": 404}', 404);
      }),
    );
    final c = Collection.fromJson(_body(visibility: 'public', role: 'viewer', lines: const [line]));
    await tester.pumpWidget(
      _app(
        CollectionMapScreen(
          api: api,
          collection: c,
          map: const SizedBox.expand(key: Key('map')),
        ),
      ),
    );
    expect(find.byKey(const Key('map')), findsOneWidget);
    expect(find.byKey(const Key('map-layers')), findsOneWidget);
    expect(find.text('Mit Freunden'), findsOneWidget);
    await tester.tap(find.byKey(const Key('collection-map-i1')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final call = asked.firstWhere((u) => u.path.startsWith('/api/v1/routes/$_route'), orElse: () => fail('$asked'));
    expect(call.queryParameters['t'], 'c.$_collection');
  });
}
