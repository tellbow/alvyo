import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/protected_areas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(WidgetTester tester, DateTime? asOf) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ProtectedAreas(Future<Along>.value((areas: <ProtectedArea>[], notices: <Notice>[], asOf: asOf))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('last known hints say from when', (tester) async {
    await show(tester, DateTime.utc(2026, 10, 12, 8));
    expect(find.textContaining('Stand 12.10.2026'), findsOneWidget);
  });

  testWidgets('current hints say nothing of it', (tester) async {
    await show(tester, null);
    expect(find.byKey(const Key('areas-as-of')), findsNothing);
  });
}
