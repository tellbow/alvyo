import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/screens/login_screen.dart';
import 'package:alvyo/session.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  /// The login screen of a release build, then «Konto erstellen».
  Future<void> openSignup(WidgetTester tester, Future<http.Response> Function(http.Request) answer) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LoginScreen(session: Session(), onLoggedIn: (_) {}, showServer: false, client: MockClient(answer)),
      ),
    );
    await tester.tap(find.byKey(const Key('signup')));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, {String username = 'anna_b'}) async {
    await tester.enterText(find.byKey(const Key('signup-email')), 'anna@example.ch');
    await tester.enterText(find.byKey(const Key('signup-username')), username);
    await tester.enterText(find.byKey(const Key('signup-name')), 'Anna');
    await tester.enterText(find.byKey(const Key('signup-password')), 'sehr-geheim-123');
    await tester.tap(find.byKey(const Key('signup-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('signs up in the app, not on the website, and says to confirm the address', (tester) async {
    http.Request? asked;
    await openSignup(tester, (r) async {
      asked = r;
      return http.Response('', 202);
    });
    await fill(tester);
    expect(asked?.url.toString(), 'https://alvyo.tellbow.ch/api/v1/auth/signup');
    expect(jsonDecode(asked!.body), {
      'email': 'anna@example.ch',
      'username': 'anna_b',
      'display_name': 'Anna',
      'password': 'sehr-geheim-123',
      'locale': 'de',
    });
    expect(find.byKey(const Key('signup-sent')), findsOneWidget);
    expect(find.textContaining('anna@example.ch'), findsOneWidget);
  });

  testWidgets('a username taken shows at its field', (tester) async {
    await openSignup(
      tester,
      (_) async => http.Response(
        jsonEncode({
          'status': 409,
          'detail': 'username taken',
          'errors': [
            {'location': 'body.username', 'message': 'taken'},
          ],
        }),
        409,
        headers: {'content-type': 'application/problem+json'},
      ),
    );
    await fill(tester);
    expect(find.text('Dieser Benutzername ist vergeben.'), findsOneWidget);
  });

  testWidgets('a username the server would refuse is not sent', (tester) async {
    var asked = false;
    await openSignup(tester, (_) async {
      asked = true;
      return http.Response('', 202);
    });
    await fill(tester, username: 'Anna B');
    expect(asked, isFalse);
    // the hint below the field and the error in its place
    expect(find.text('3–30 Zeichen: Kleinbuchstaben, Ziffern und _'), findsOneWidget);
  });
}
