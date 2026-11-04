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

const _achievements = {
  'cantons': ['BE', 'GL', 'SG'],
  'cantons_total': 26,
  'official': [
    {'kind': 'national', 'done': 1, 'total': 7},
  ],
  'summits': [
    {'name': 'Piz Sardona', 'ele': 3056},
    {'name': 'Foopass'},
  ],
  'huts': ['Spitzmeilenhütte'],
};

http.Response _json(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  Future<List<Uri>> open(WidgetTester tester, {bool nothing = false}) async {
    final asked = <Uri>[];
    final api = Api(
      'https://example.ch',
      client: MockClient((r) async {
        asked.add(r.url);
        final y2025 = r.url.queryParameters['year'] == '2025';
        if (r.url.path.endsWith('/me/achievements')) return _json(_achievements);
        return _json({
          'total': _totals(0, nothing ? 0 : 3),
          'years': nothing ? [] : [_totals(2026, 2), _totals(2025, 1)],
          'items': nothing
              ? []
              : y2025
              ? [_item('Alt', '2025-06-01')]
              : [_item('Neu', '2026-06-01'), _item('Alt', '2025-06-01')],
        });
      }),
    );
    tester.view.physicalSize = const Size(1000, 2600);
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

  testWidgets('one\'s achievements: cantons, official routes, summits and huts', (tester) async {
    await open(tester);
    final list = find.byKey(const Key('hiked-list'));
    await tester.scrollUntilVisible(
      find.text('Spitzmeilenhütte'),
      200,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    expect(find.text('BE'), findsOneWidget);
    expect(find.text('Kantone: 3 von 26'), findsOneWidget);
    expect(find.text('National: 1 von 7'), findsOneWidget);
    expect(find.text('Gipfel: 2'), findsOneWidget);
    expect(find.textContaining('Piz Sardona'), findsOneWidget);
  });

  testWidgets('someone else\'s: only what they share, and the years change the numbers alone', (tester) async {
    final asked = <Uri>[];
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HikedScreen(
          api: Api(
            'https://example.ch',
            client: MockClient((r) async {
              asked.add(r.url);
              return _json({
                'username': 'anna',
                'display_name': 'Anna',
                'total': _totals(0, 3),
                'years': [_totals(2026, 2), _totals(2025, 1)],
                'lines': [
                  [
                    [8.0, 46.5],
                    [8.1, 46.6],
                  ],
                ],
              });
            }),
          ),
          username: 'anna',
          map: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Wanderungen von Anna'), findsOneWidget);
    expect(find.text('Erfolge'), findsNothing);
    final stats = find.byKey(const Key('hiked-stats'));
    expect(find.descendant(of: stats, matching: find.text('3')), findsOneWidget);

    await tester.tap(find.byKey(const Key('hiked-year-2025')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: stats, matching: find.text('1')), findsOneWidget);
    expect(asked, hasLength(1));
    expect(asked.single.path, endsWith('/users/anna/hiked'));
  });

  testWidgets('nothing hiked yet says how to start', (tester) async {
    await open(tester, nothing: true);
    expect(find.byKey(const Key('hiked-empty')), findsOneWidget);
    expect(find.byKey(const Key('hiked-stats')), findsNothing);
  });
}
