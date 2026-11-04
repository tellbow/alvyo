import 'dart:convert';

import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/screens/hiked_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _totals(int year, int hikes) => {
  if (year != 0) 'year': year,
  'hikes': hikes,
  'distance_m': 12000.0 * hikes,
  'ascent_m': 800.0 * hikes,
  'time_s': 7200 * hikes,
  'longest_m': 12000.0,
  'longest_title': 'Lang',
  'highest_m': 2500.0,
};

Map<String, dynamic> _item(String title, String on) => {
  'kind': 'route',
  'id': '01a00000-0000-7000-8000-000000000001',
  'title': title,
  'on': on,
  'distance_m': 12000.0,
  'ascent_m': 800.0,
  'time_s': 7200,
  'lines': [
    [
      [8.0, 46.5],
      [8.1, 46.6],
    ],
  ],
};

void main() {
  Future<List<Uri>> open(WidgetTester tester, {bool nothing = false}) async {
    final asked = <Uri>[];
    final api = Api(
      'https://example.ch',
      client: MockClient((r) async {
        asked.add(r.url);
        final y2025 = r.url.queryParameters['year'] == '2025';
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'total': _totals(0, nothing ? 0 : 3),
              'years': nothing ? [] : [_totals(2026, 2), _totals(2025, 1)],
              'items': nothing
                  ? []
                  : y2025
                  ? [_item('Alt', '2025-06-01')]
                  : [_item('Neu', '2026-06-01'), _item('Alt', '2025-06-01')],
            }),
          ),
          200,
        );
      }),
    );
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HikedScreen(api: api, map: const SizedBox()),
      ),
    );
    await tester.pumpAndSettle();
    return asked;
  }

  testWidgets('all years at first, then a year: its numbers and its hikes', (tester) async {
    final asked = await open(tester);
    final stats = find.byKey(const Key('hiked-stats'));
    expect(find.descendant(of: stats, matching: find.text('3')), findsOneWidget);
    expect(find.text('Neu'), findsOneWidget);

    await tester.tap(find.byKey(const Key('hiked-year-2025')));
    await tester.pumpAndSettle();
    expect(asked.last.queryParameters['year'], '2025');
    expect(find.descendant(of: stats, matching: find.text('1')), findsOneWidget);
    expect(find.text('Neu'), findsNothing);
    expect(find.text('Alt'), findsOneWidget);

    await tester.tap(find.byKey(const Key('hiked-year-all')));
    await tester.pumpAndSettle();
    expect(asked.last.queryParameters.containsKey('year'), isFalse);
    expect(find.text('Neu'), findsOneWidget);
  });

  testWidgets('nothing hiked yet says how to start', (tester) async {
    await open(tester, nothing: true);
    expect(find.byKey(const Key('hiked-empty')), findsOneWidget);
    expect(find.byKey(const Key('hiked-stats')), findsNothing);
  });
}
