import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/screens/friends_screen.dart';

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  // A request waiting, a search, asking and accepting.
  testWidgets('friends: search and ask, accept a request, a suggestion not wanted', (tester) async {
    tester.view.physicalSize = const Size(400, 2400); // all of it at once
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = <String>[];
    var annaAccepted = false, miaDismissed = false;
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}${req.url.hasQuery ? '?${req.url.query}' : ''}');
      return switch ((req.method, req.url.path)) {
        ('GET', '/api/v1/me/friends') => _json({
          'friends': [
            if (annaAccepted)
              {'username': 'anna', 'display_name': 'Anna Alp', 'friend': 'friends', 'since': '2026-10-01T10:00:00Z'},
          ],
          'incoming': [
            if (!annaAccepted)
              {'username': 'anna', 'display_name': 'Anna Alp', 'friend': 'incoming', 'since': '2026-10-01T10:00:00Z'},
          ],
          'outgoing': <Object>[],
        }),
        ('GET', '/api/v1/me/friend-link') => _json({'token': 'abc'}),
        ('GET', '/api/v1/users') => _json({
          'users': [
            {'username': 'beat', 'display_name': 'Beat Berg', 'friend': 'none', 'since': '2026-09-01T10:00:00Z'},
          ],
        }),
        ('GET', '/api/v1/me/friend-suggestions') => _json({
          'users': [
            if (!miaDismissed)
              {
                'username': 'mia',
                'display_name': 'Mia Gerber',
                'friend': 'none',
                'since': '2026-09-01T10:00:00Z',
                'tours': 3,
                'mutual': 2,
              },
          ],
        }),
        ('DELETE', '/api/v1/me/friend-suggestions/mia') => () {
          miaDismissed = true;
          return http.Response('', 204);
        }(),
        ('PUT', '/api/v1/users/beat/friend') => _json({'friend': 'requested'}),
        ('PUT', '/api/v1/users/anna/friend') => () {
          annaAccepted = true;
          return _json({'friend': 'friends'});
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
        home: FriendsScreen(
          api: Api('http://test', token: 't', client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Anfragen an dich'), findsOneWidget);
    expect(find.byKey(const Key('friends-empty')), findsOneWidget);
    // Profiles to discover before searching; a suggestion with only the number in common.
    expect(calls, contains('GET /api/v1/users'));
    expect(find.text('Leute, die du kennen könntest'), findsOneWidget);
    expect(find.text('3 Touren · 2 gemeinsame Freunde'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dismiss-mia')));
    await tester.pumpAndSettle();
    expect(calls, contains('DELETE /api/v1/me/friend-suggestions/mia'));
    expect(find.text('Mia Gerber'), findsNothing);

    await tester.enterText(find.byKey(const Key('friends-search')), 'Beat');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(calls, contains('GET /api/v1/users?q=Beat'));
    await tester.tap(find.byKey(const Key('friend-add')));
    await tester.pumpAndSettle();
    expect(find.text('Anfrage gesendet'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('friend-accept')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('friend-accept')));
    await tester.pumpAndSettle();
    expect(find.text('Anfragen an dich'), findsNothing, reason: 'the lists load anew');
    expect(find.text('✓ Befreundet'), findsOneWidget);
  });

  // A friend's invite link opened in the app: who sent it, then friends.
  testWidgets('an invite link makes friends', (tester) async {
    const token = 'AbCdEfGhIjKlMnOpQrStUv';
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      return switch ((req.method, req.url.path)) {
        ('GET', '/api/v1/me') => _json({'id': 'u1', 'username': 'carla', 'display_name': 'Carla'}),
        ('GET', '/api/v1/friend-invites/$token') => _json({'username': 'beat', 'display_name': 'Beat Berg'}),
        ('POST', '/api/v1/friend-invites/$token') => _json({'username': 'beat', 'display_name': 'Beat Berg'}),
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
        home: InviteScreen(
          api: Api('http://test', token: 't', client: client),
          token: token,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Beat Berg lädt dich ein'), findsOneWidget);
    await tester.tap(find.byKey(const Key('friend-invite-accept')));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /api/v1/friend-invites/$token'));
    expect(find.byKey(const Key('friend-invite-done')), findsOneWidget);
  });
}
