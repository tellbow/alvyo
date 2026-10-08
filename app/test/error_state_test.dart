import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/screens/error_state.dart';

void main() {
  Future<void> show(WidgetTester tester, Object error, VoidCallback retry) => tester.pumpWidget(
    MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ErrorState(error: error, onRetry: retry),
      ),
    ),
  );

  testWidgets('offline: says so and tries again', (tester) async {
    var tries = 0;
    await show(tester, Exception('no connection'), () => tries++);
    expect(find.text('Der Server ist nicht erreichbar.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('error-retry')));
    expect(tries, 1);
  });

  testWidgets('gone or private: says so, nothing to try again', (tester) async {
    await show(tester, ApiException(404, 'not found'), () {});
    expect(find.textContaining('gibt es nicht'), findsOneWidget);
    expect(find.byKey(const Key('error-retry')), findsNothing);
  });
}
