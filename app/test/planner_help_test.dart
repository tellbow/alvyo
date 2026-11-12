import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/planner_help.dart';
import 'package:alvyo/settings.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('the planner help can be hidden and brought back', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: PlannerHelp()),
      ),
    );
    expect(find.text('Ziel'), findsOneWidget);

    await tester.tap(find.byKey(const Key('planner-help-hide')));
    await tester.pump();
    expect(find.byKey(const Key('planner-help')), findsNothing);
    expect(AppSettings.instance.plannerHelpHidden.value, isTrue);

    await tester.tap(find.byKey(const Key('planner-help-open')));
    await tester.pump();
    expect(find.byKey(const Key('planner-help')), findsOneWidget);
  });
}
