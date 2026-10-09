import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/screens/account_screens.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  // Created: the token shown once; listed with when it was used; revoked
  // after asking.
  testWidgets('access tokens: create, shown once, revoke', (tester) async {
    final tokens = <Map<String, Object?>>[
      {'id': 'a1', 'name': 'Skript', 'created_at': '2026-10-01T10:00:00Z', 'last_used_at': '2026-10-08T09:00:00Z'},
    ];
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      return switch ((req.method, req.url.path)) {
        ('GET', '/api/v1/me/tokens') => _json({'tokens': tokens}),
        ('POST', '/api/v1/me/tokens') => () {
          final t = {'id': 'b2', 'name': (jsonDecode(req.body) as Map)['name'], 'created_at': '2026-10-09T10:00:00Z'};
          tokens.insert(0, t);
          return _json({...t, 'token': 'alvyo_pat_geheim'}, 201);
        }(),
        ('DELETE', '/api/v1/me/tokens/a1') => () {
          tokens.removeWhere((t) => t['id'] == 'a1');
          return http.Response('', 204);
        }(),
        _ => http.Response('', 404),
      };
    });
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
        home: AccessTokensScreen(
          api: Api('http://test', token: 't', client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('http://test/api/v1/mcp'), findsOneWidget);
    expect(find.text('erstellt am 01.10.2026 · zuletzt benutzt am 08.10.2026'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('token-name')), 'Claude Desktop');
    await tester.pump();
    await tester.tap(find.byKey(const Key('token-create')));
    await tester.pumpAndSettle();
    expect(find.text('alvyo_pat_geheim'), findsOneWidget);
    expect(find.text('Claude Desktop'), findsOneWidget);
    expect(find.textContaining('noch nie benutzt'), findsOneWidget);

    await tester.tap(find.byTooltip('Widerrufen').last);
    await tester.pumpAndSettle();
    expect(
      find.text('«Skript» widerrufen? Programme mit diesem Token kommen dann nicht mehr in dein Konto.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('token-revoke-ok')));
    await tester.pumpAndSettle();
    expect(calls, contains('DELETE /api/v1/me/tokens/a1'));
    expect(find.text('Skript'), findsNothing);
  });
}
