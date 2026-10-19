import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/apple_sign_in.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/screens/login_screen.dart';
import 'package:alvyo/session.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<void> login(WidgetTester tester, http.Response answer) async {
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
        home: LoginScreen(session: Session(), onLoggedIn: (_) {}, client: MockClient((_) async => answer)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('server')), 'https://alvyo.test');
    await tester.enterText(find.byKey(const Key('login')), 'anna');
    await tester.enterText(find.byKey(const Key('password')), 'sehr-geheim-123');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
  }

  http.Response problem(int status, String detail, [List<Map<String, String>> errors = const []]) => http.Response(
    jsonEncode({'status': status, 'detail': detail, 'errors': errors}),
    status,
    headers: {'content-type': 'application/problem+json'},
  );

  testWidgets('an address not confirmed yet: says so, a link is on its way', (tester) async {
    await login(
      tester,
      problem(403, 'e-mail address not confirmed; a link is in your inbox', [
        {'location': 'body.login', 'message': 'unverified'},
      ]),
    );
    expect(
      find.text('Bestätige zuerst deine E-Mail-Adresse. Wir haben dir einen neuen Link geschickt.'),
      findsOneWidget,
    );
  });

  testWidgets('a wrong password', (tester) async {
    await login(tester, problem(401, 'invalid login or password'));
    expect(find.text('E-Mail/Benutzername oder Passwort ist falsch.'), findsOneWidget);
  });

  testWidgets('a server typed before the last one is read stays', (tester) async {
    final last = Completer<String>();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LoginScreen(session: _SlowSession(last.future), onLoggedIn: (_) {}),
      ),
    );
    await tester.enterText(find.byKey(const Key('server')), 'http://localhost:5173');
    last.complete('https://alvyo.tellbow.ch');
    await tester.pump();
    expect(find.text('http://localhost:5173'), findsOneWidget);
  });

  testWidgets('a release build has no server field and logs in to alvyo.tellbow.ch', (tester) async {
    Uri? asked;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LoginScreen(
          session: _SlowSession(Future.value('http://localhost:5173')),
          onLoggedIn: (_) {},
          showServer: false,
          client: MockClient((r) async {
            asked = r.url;
            return problem(401, 'invalid login or password');
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('server')), findsNothing);
    await tester.enterText(find.byKey(const Key('login')), 'anna');
    await tester.enterText(find.byKey(const Key('password')), 'sehr-geheim-123');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    expect(asked?.host, 'alvyo.tellbow.ch');
  });

  group('Sign in with Apple', () {
    const credential = (identityToken: 'id-token', authorizationCode: 'code', name: 'Anna Muster');

    /// The login screen against a server that offers [providers] and
    /// answers the app's Apple sign-in with [native].
    Future<List<http.Request>> open(
      WidgetTester tester, {
      List<String> providers = const ['google', 'apple'],
      http.Response? native,
      AppleCredential? sheet = credential,
      void Function()? loggedIn,
      List<String>? nonces,
    }) async {
      final asked = <http.Request>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LoginScreen(
            session: Session(),
            onLoggedIn: (_) => loggedIn?.call(),
            showServer: false,
            appleSheet: (nonce) async {
              nonces?.add(nonce);
              return sheet;
            },
            client: MockClient((r) async {
              asked.add(r);
              if (r.url.path.endsWith('/auth/providers')) {
                return http.Response(
                  jsonEncode({
                    'providers': [
                      for (final p in providers) {'id': p, 'name': p},
                    ],
                  }),
                  200,
                );
              }
              return native ?? problem(500, 'unexpected');
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return asked;
    }

    testWidgets('logs in with the sheet\'s tokens and the nonce it was asked with', (tester) async {
      var loggedIn = false;
      final nonces = <String>[];
      final asked = await open(
        tester,
        nonces: nonces,
        loggedIn: () => loggedIn = true,
        native: http.Response(
          jsonEncode({
            'user': {'id': 'u1', 'username': 'anna_muster', 'display_name': 'Anna Muster', 'speed_factor': 1.0},
          }),
          200,
          headers: {'set-cookie': 'alvyo_session=s3ss10n; Path=/; HttpOnly'},
        ),
      );
      await tester.tap(find.text('Mit Apple fortfahren'));
      await tester.pumpAndSettle();
      final sent = asked.last;
      expect(sent.url.path, '/api/v1/auth/oidc/apple/native');
      expect(jsonDecode(sent.body), {
        'identity_token': 'id-token',
        'authorization_code': 'code',
        'nonce': nonces.single,
        'name': 'Anna Muster',
        'locale': 'de',
      });
      expect(nonces.single.length, greaterThan(40));
      expect(loggedIn, isTrue);
    });

    testWidgets('an address with an account already: how to connect Apple', (tester) async {
      await open(tester, native: problem(409, 'an account has this e-mail address'));
      await tester.tap(find.text('Mit Apple fortfahren'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Es gibt schon ein Konto mit dieser E-Mail-Adresse.'), findsOneWidget);
    });

    testWidgets('cancelled at the sheet: nothing sent, no error', (tester) async {
      final asked = await open(tester, sheet: null);
      await tester.tap(find.text('Mit Apple fortfahren'));
      await tester.pumpAndSettle();
      expect(asked.where((r) => r.url.path.endsWith('/native')), isEmpty);
      expect(find.textContaining('Fehler'), findsNothing);
    });

    testWidgets('not offered when the server has no Apple sign-in', (tester) async {
      await open(tester, providers: ['google']);
      expect(find.byKey(const Key('apple')), findsNothing);
    });
  });
}

/// Reads the last server slowly, as secure storage on Android can.
class _SlowSession extends Session {
  _SlowSession(this.last);

  final Future<String> last;

  @override
  Future<String> lastServer() => last;
}
