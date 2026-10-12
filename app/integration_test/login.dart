import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Logs in as the demo account if the app asks: waits until the login
/// screen or the app's tab bar shows (slower on the Android emulator than
/// on the simulator), as a saved session skips the login.
Future<void> logInIfAsked(WidgetTester tester, {String server = 'http://localhost:5173'}) async {
  final login = find.byKey(const Key('server'));
  final home = find.byKey(const Key('tab-profile'));
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (login.evaluate().isEmpty && home.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) throw TestFailure('neither the login nor the app showed');
    await tester.pump(const Duration(milliseconds: 250));
  }
  if (login.evaluate().isEmpty) return;
  await tester.enterText(login, server);
  await tester.enterText(find.byKey(const Key('login')), 'appdemo');
  await tester.enterText(find.byKey(const Key('password')), 'sehr-geheim-123');
  await tester.tap(find.byKey(const Key('submit')));
}
