import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:odysgeh/api.dart';
import 'package:odysgeh/l10n/app_localizations.dart';
import 'package:odysgeh/navigation/alerts.dart';
import 'package:odysgeh/navigation/speech.dart';
import 'package:odysgeh/navigation/tracker.dart';
import 'package:odysgeh/screens/navigate_screen.dart';

class _QuietAlerts extends Alerts {
  @override
  Future<void> init() async {}
  @override
  Future<void> offRoute(String title, String body) async {}
  @override
  Future<void> clear() async {}
}

class _QuietSpeech extends Speech {
  @override
  Future<void> say(String text, String language) async {}
}

/// Against the local dev server (see offline_test.dart; the demo account
/// needs a verified address and a contact): a hike shared with a contact
/// sends its position, «Später» moves the end, finishing ends the sharing.
///   `flutter test integration_test/live_test.dart -d SIMULATOR_ID`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(WidgetTester tester, Finder f, {Duration timeout = const Duration(seconds: 60)}) async {
    final end = DateTime.now().add(timeout);
    while (f.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $f');
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('a shared hike: position for the contacts, later, end', (tester) async {
    const server = 'http://localhost:5173';
    final api = Api(server);
    await api.login('appdemo', 'sehr-geheim-123');
    final summary = (await api.routes()).firstWhere((r) => r.title == 'Sargans–Weisstannen');
    final route = await api.route(summary.id);
    final contacts = await api.contacts();
    expect(contacts, isNotEmpty, reason: 'the demo account needs a contact');
    final end = DateTime.now().add(const Duration(hours: 6));
    final live = await api.startLive(
      routeId: route.id,
      title: route.title,
      contactIds: [contacts.first.id],
      expectedEnd: end,
    );
    // The page the contacts open from their e-mail.
    Future<Map<String, dynamic>> view() async {
      final r = await http.get(Uri.parse('$server/api/v1/live/view/${live.token}'));
      return jsonDecode(r.body) as Map<String, dynamic>;
    }

    final positions = StreamController<Fix>();
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
        home: NavigateScreen(
          api: api,
          route: route,
          positions: () => positions.stream,
          recordings: Directory.systemTemp.createTempSync('recordings'),
          alerts: _QuietAlerts(),
          speech: _QuietSpeech(),
          live: live,
        ),
      ),
    );
    await waitFor(tester, find.byKey(const Key('nav-live')));
    final p = route.line[40];
    positions.add(Fix(lon: p[0], lat: p[1], time: DateTime.now().toUtc()));
    await waitFor(tester, find.byKey(const Key('nav-progress')));
    await tester.pump(const Duration(seconds: 2));
    final v = await tester.runAsync(view);
    expect((v!['last'] as Map<String, dynamic>)['lon'], closeTo(p[0], 1e-6));
    expect(v['ended_at'], isNull);

    await tester.tap(find.byKey(const Key('nav-live-later')));
    await tester.pump(const Duration(seconds: 2));
    final later = await tester.runAsync(view);
    expect(DateTime.parse(later!['expected_end'] as String).difference(end).inMinutes, closeTo(60, 1));

    await tester.tap(find.byKey(const Key('nav-finish')));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('nav-finish-confirm')));
    await tester.pump(const Duration(seconds: 2));
    final ended = await tester.runAsync(view);
    expect(ended!['ended_at'], isNotNull);
  });
}
