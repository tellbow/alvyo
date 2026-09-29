import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/reminders.dart';
import 'package:alvyo/screens/people_section.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

JourneyDetail _journey({bool secondBooked = false, String role = 'owner'}) => JourneyDetail.fromJson({
  'id': 'j1',
  'title': 'Via Alpina',
  'role': role,
  'can_edit': role != 'viewer',
  'totals': {'distance_m': 0.0, 'ascent_m': 0.0, 'descent_m': 0.0, 'duration_s': 0, 'sac_grade': 0, 'sac_max': 0},
  'progress': {'stages_done': 0, 'stages_total': 3},
  'stage_list': [
    for (final (i, booked) in [true, secondBooked, false].indexed)
      {
        'id': 's${i + 1}',
        'title': i == 0 ? 'Gaflei – Sargans' : '',
        'version': 1,
        'status': 'planned',
        'accommodation_booked': booked,
      },
  ],
});

void main() {
  test('three weeks, two days and one day before the start, only those to come', () {
    final start = DateTime(2027, 7, 1);
    final all = journeyReminders('j1', start, unbooked: true, now: DateTime(2027, 6, 1));
    expect(
      [for (final r in all) (r.kind, r.at)],
      [
        ('book', DateTime(2027, 6, 10, 9)),
        ('weather', DateTime(2027, 6, 29, 18)),
        ('start', DateTime(2027, 6, 30, 18)),
      ],
    );
    expect({for (final r in all) r.id}, hasLength(3));
    // Later on, fewer; all booked, none to book; the same ids each time.
    expect(
      [for (final r in journeyReminders('j1', start, unbooked: true, now: DateTime(2027, 6, 29, 19))) r.kind],
      ['start'],
    );
    expect(
      [for (final r in journeyReminders('j1', start, unbooked: false, now: DateTime(2027, 6, 1))) r.kind],
      ['weather', 'start'],
    );
    expect(journeyReminders('j1', start, unbooked: true, now: DateTime(2027, 6, 1)).first.id, all.first.id);
    expect(journeyReminders('j2', start, unbooked: true, now: DateTime(2027, 6, 1)).first.id, isNot(all.first.id));
  });

  test('nights to book: planned stages but the last', () {
    expect(hasUnbooked(_journey()), isTrue);
    expect(hasUnbooked(_journey(secondBooked: true)), isFalse);
  });

  testWidgets('the owner adds someone and chooses their stages', (tester) async {
    final calls = <String>[];
    var people = <Object>[];
    final api = Api(
      'https://alvyo.test',
      token: 't',
      client: MockClient((req) async {
        calls.add('${req.method} ${req.url.path} ${req.body}');
        if (req.method == 'POST') {
          people = [
            {
              'id': 'g1',
              'username': 'anna',
              'display_name': 'Anna',
              'stages': ['s1', 's2', 's3'],
            },
          ];
        } else if (req.method == 'PUT') {
          final stages = (jsonDecode(req.body) as Map<String, dynamic>)['stages'];
          people = [
            {'id': 'g1', 'username': 'anna', 'display_name': 'Anna', 'stages': stages},
          ];
        }
        return _json({'people': people});
      }),
    );
    var shown = <Person>[];
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
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PeopleSection(
              api: api,
              journey: _journey(),
              people: shown,
              onChanged: (p) => setState(() => shown = p),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Noch niemand'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('people-who')), 'anna');
    await tester.tap(find.byKey(const Key('people-add')));
    await tester.pumpAndSettle();
    expect(calls.last, 'POST /api/v1/journeys/j1/people {"username":"anna"}');
    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('1 · 2 · 3'), findsOneWidget);

    await tester.tap(find.text('Anna'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('person-stage-0')));
    await tester.pumpAndSettle();
    expect(calls.last, 'PUT /api/v1/journeys/j1/people/g1 {"stages":["s2","s3"]}');
    expect(find.byKey(const Key('person-remove')), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('2 · 3'), findsOneWidget);
  });
}
