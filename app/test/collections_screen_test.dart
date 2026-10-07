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
import 'package:alvyo/screens/collections_screen.dart';

const _collection = '0199a000-0000-7000-8000-00000000000c';
const _route = '0199a000-0000-7000-8000-00000000000a';

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _body({required String visibility, required String role, int hidden = 0}) => {
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
    },
  ],
};

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
}
