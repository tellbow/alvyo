import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/screens/live_sheet.dart';

void main() {
  final route = RouteDetail.fromJson({
    'id': 'r1',
    'title': 'Gratweg',
    'owner_username': 'anna',
    'totals': {
      'distance_m': 5000.0,
      'ascent_m': 300.0,
      'descent_m': 300.0,
      'duration_s': 7200,
      'sac_grade': 2,
      'sac_max': 2,
    },
    'legs': <Object>[],
  });

  Future<(LiveShare?, Map<String, dynamic>?)> run(
    WidgetTester tester, {
    required bool share,
    List<Object>? contacts,
  }) async {
    Map<String, dynamic>? sent;
    final api = Api(
      'https://alvyo.test',
      token: 't',
      client: MockClient((req) async {
        final json = {'content-type': 'application/json; charset=utf-8'};
        switch (req.url.path) {
          case '/api/v1/me/contacts':
            return http.Response(
              jsonEncode({
                'contacts':
                    contacts ??
                    [
                      {'id': 'c1', 'name': 'Bea', 'email': 'bea@example.ch'},
                      {'id': 'c2', 'name': 'Cyril', 'email': 'cyril@example.ch'},
                    ],
              }),
              200,
              headers: json,
            );
          case '/api/v1/me':
            return http.Response(
              jsonEncode({'id': 'u1', 'username': 'anna', 'display_name': 'Anna', 'speed_factor': 1.5}),
              200,
              headers: json,
            );
          case '/api/v1/live':
            sent = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'id': 'l1',
                'token': 'tok',
                'expected_end': sent!['expected_end'],
                'recipients': ['Bea'],
              }),
              201,
              headers: json,
            );
        }
        return http.Response('', 404);
      }),
    );
    final dir = Directory.systemTemp.createTempSync('recordings');
    addTearDown(() => dir.deleteSync(recursive: true));
    LiveShare? result;
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(), // a new navigator: no sheet left from a call before
        locale: const Locale('de'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              key: const Key('go'),
              onPressed: () async {
                result = await askToShare(context, api: api, route: route, recordings: dir);
                done = true;
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('go')));
    for (var i = 0; i < 50 && find.byKey(const Key('live-share')).evaluate().isEmpty && !done; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (!done && find.byKey(const Key('live-share')).evaluate().isNotEmpty) {
      await tester.pumpAndSettle(); // the sheet has slid up
      if (share) {
        await tester.ensureVisible(find.byKey(const Key('live-contact-c1')));
        await tester.tap(find.byKey(const Key('live-contact-c1')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('live-share')));
        await tester.tap(find.byKey(const Key('live-share')));
      } else {
        await tester.ensureVisible(find.byKey(const Key('live-skip')));
        await tester.tap(find.byKey(const Key('live-skip')));
      }
      for (var i = 0; i < 50 && !done; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    return (result, sent);
  }

  testWidgets('share with a chosen contact; the end at one\'s pace plus an hour', (tester) async {
    final before = DateTime.now();
    final (live, sent) = await run(tester, share: true);
    expect(live?.id, 'l1');
    expect(sent!['contact_ids'], ['c1']);
    expect(sent['route_id'], 'r1');
    // 2 h at pace 1.5 is 3 h, and one more.
    final end = DateTime.parse(sent['expected_end'] as String);
    expect(end.difference(before).inMinutes, closeTo(240, 2));
  });

  testWidgets('not shared: skipped, or without contacts', (tester) async {
    expect((await run(tester, share: false)).$1, isNull);
    expect((await run(tester, share: true, contacts: [])).$1, isNull, reason: 'no sheet without contacts');
  });
}
