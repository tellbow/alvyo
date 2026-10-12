import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
}

/// Reads the last server slowly, as secure storage on Android can.
class _SlowSession extends Session {
  _SlowSession(this.last);

  final Future<String> last;

  @override
  Future<String> lastServer() => last;
}
