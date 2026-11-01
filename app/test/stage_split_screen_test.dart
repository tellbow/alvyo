import 'dart:convert';

import 'package:alvyo/api.dart';
import 'package:alvyo/elevation_profile.dart';
import 'package:alvyo/format.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/l10n/app_localizations_de.dart';
import 'package:alvyo/screens/import_screen.dart';
import 'package:alvyo/screens/stage_split_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _stage(double from, double to, {String? end}) => {
  'start_place': null,
  'end_place': end == null
      ? null
      : {
          'id': end,
          'kind': 'hut',
          'name': end,
          'detail': '',
          'at': [to, 46.7],
          'distance_m': 0.0,
          'website': '',
        },
  'earlier': null,
  'later': null,
  'accommodation': end ?? '',
  'totals': {
    'distance_m': 5000.0,
    'ascent_m': 100.0,
    'descent_m': 50.0,
    'duration_s': 7200,
    'sac_grade': 1,
    'sac_max': 1,
  },
  'over_max': false,
  'under_min': false,
  'profile': 'hike',
  'anchors': [
    {'lon': from, 'lat': 46.7},
    {'lon': to, 'lat': 46.7},
  ],
  'legs': [
    {
      'coordinates': [
        [from, 46.7, 500],
        [to, 46.7, 600],
      ],
    },
  ],
};

Map<String, dynamic> _proposal(List<Map<String, dynamic>> stages) => {
  'stages': stages,
  'target_s': 7200,
  'min_s': 0,
  'max_s': 10800,
};

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('de'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

void main() {
  const line = [
    [7.0, 46.7, 500.0],
    [8.0, 46.7, 600.0],
  ];

  testWidgets('a tap on the profile splits a stage there, a stage joins the next, and nothing is saved before asked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final asked = <({int days, List<String>? ends})>[];
    var created = 0;
    final api = Api(
      'https://alvyo.test',
      token: 't',
      client: MockClient((req) async {
        if (req.url.path.endsWith('/journeys') && req.method == 'POST') {
          created++;
          return http.Response('{"detail":"stop here"}', 500);
        }
        return http.Response('{}', 404);
      }),
    );
    await tester.pumpWidget(
      _app(
        StageSplitScreen(
          api: api,
          line: line,
          title: 'Lange Tour',
          durationS: 3 * 6 * 3600,
          showMap: false,
          propose: (days, ends) async {
            asked.add((days: days, ends: ends));
            final free = ends ?? const [];
            return Proposal.fromJson(
              _proposal(
                free.isEmpty
                    ? [_stage(7, 7.5, end: 'hut'), _stage(7.5, 8)]
                    : [_stage(7, 7.25), _stage(7.25, 7.5, end: 'hut'), _stage(7.5, 8)],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stages-stage-0')), findsNothing);
    expect(
      tester.widget<TextField>(find.byKey(const Key('stages-days'))).controller!.text,
      '3',
      reason: '18 h at 6 h a day',
    );

    await tester.enterText(find.byKey(const Key('stages-days')), '2');
    await tester.tap(find.byKey(const Key('stages-propose')));
    await tester.pumpAndSettle();
    expect(asked.single, (days: 2, ends: null));
    expect(find.byKey(const Key('stages-stage-1')), findsOneWidget);
    expect(find.byKey(const Key('stages-merge-0')), findsNothing, reason: 'two days stay two');

    // In the first half of the profile: the first stage.
    final box = tester.getRect(find.byKey(const Key('elevation-profile')));
    await tester.tapAt(box.centerLeft + Offset(box.width * 0.3, 0));
    await tester.pumpAndSettle();
    expect(asked.last.days, 3);
    expect(asked.last.ends!.length, 2);
    expect(asked.last.ends![0], startsWith('@'));
    expect(asked.last.ends![1], 'hut');
    expect(
      tester.widget<Text>(find.byKey(const Key('stages-end-0'))).data,
      '→ ${AppLocalizationsDe().stagesEndAt(formatDistance(5000))}',
      reason: 'a spot says how far along',
    );

    await tester.tap(find.byKey(const Key('stages-merge-0')));
    await tester.pumpAndSettle();
    expect(asked.last.days, 2);
    expect(asked.last.ends, ['hut']);

    expect(created, 0);
    await tester.tap(find.byKey(const Key('stages-create')));
    await tester.pumpAndSettle();
    expect(created, 1);
    expect(find.byKey(const Key('stages-problem')), findsOneWidget);
  });

  testWidgets('a recording in as many stages as it has days splits at its nights', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fields = <Map<String, String>>[];
    final api = Api(
      'https://alvyo.test',
      token: 't',
      client: MockClient.streaming((req, body) async {
        final text = latin1.decode(await body.toBytes());
        fields.add({
          'path': req.url.path,
          'days': RegExp(r'name="days"\r\n\r\n(\d+)').firstMatch(text)?.group(1) ?? '',
        });
        final out = req.url.path.endsWith('/preview')
            ? {
                'format': 'gpx',
                'tracks': [
                  {'name': 'Zwei Tage', 'points': 2, 'distance_m': 10000, 'inside': true, 'nights': 1, 'line': line},
                ],
              }
            : _proposal([_stage(7, 7.5), _stage(7.5, 8)]);
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode(out))),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await tester.pumpWidget(
      _app(ImportScreen(api: api, bytes: utf8.encode('<gpx/>'), filename: 'zwei.gpx', showMap: false)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ElevationProfile), findsOneWidget, reason: 'its heights before anything is saved');
    await tester.tap(find.byKey(const Key('import-mode-stages')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('import-submit')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('stages-days'))).controller!.text, '2');
    await tester.tap(find.byKey(const Key('stages-propose')));
    await tester.pumpAndSettle();
    expect(fields.last, {'path': '/api/v1/imports/stages', 'days': ''});

    await tester.enterText(find.byKey(const Key('stages-days')), '3');
    await tester.tap(find.byKey(const Key('stages-propose')));
    await tester.pumpAndSettle();
    expect(fields.last['days'], '3');
  });
}
