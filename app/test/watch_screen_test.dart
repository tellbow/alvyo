import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/navigation/tracker.dart';
import 'package:alvyo/screens/watch_screen.dart';
import 'package:alvyo/watch/workouts.dart';

class FakeWorkouts implements WorkoutSource {
  FakeWorkouts(this.workouts, {this.available = true});
  final List<Workout> workouts;
  final bool available;

  @override
  Future<bool> authorize() async => available;
  @override
  Future<List<Workout>> recent({int days = 60}) async => workouts;
  @override
  Future<List<Fix>> track(Workout w) async => w.uuid == 'indoor'
      ? []
      : [
          for (var i = 0; i < 4; i++)
            Fix(
              lon: 8.04 + i * 0.001,
              lat: 46.66,
              accuracyM: i == 2 ? 50 : 5,
              time: w.start.add(Duration(minutes: i)),
            ),
        ];
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('watch'));
  tearDown(() => dir.deleteSync(recursive: true));

  final start = DateTime.utc(2026, 9, 20, 8);
  final hike = Workout(
    uuid: 'w1',
    start: start,
    end: start.add(const Duration(hours: 3, minutes: 5)),
    distanceM: 9300,
    hiking: true,
    source: 'Apple Watch',
  );
  final indoor = Workout(
    uuid: 'indoor',
    start: start,
    end: start.add(const Duration(minutes: 30)),
    hiking: false,
    source: 'iPhone',
  );

  /// Lets real file and network work finish (the spinner never settles).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  Future<void> pump(WidgetTester tester, WorkoutSource source, Api api) async {
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
        // A new screen each time, as when opened again.
        home: WatchScreen(key: UniqueKey(), api: api, source: source, importedFile: File('${dir.path}/imported.json')),
      ),
    );
    await settle(tester);
  }

  testWidgets('imports a workout with its track as a hike, once', (tester) async {
    final bodies = <Map<String, dynamic>>[];
    final api = Api(
      'https://alvyo.test',
      token: 't',
      client: MockClient((req) async {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({'id': 'route-1'}), 201);
      }),
    );
    await pump(tester, FakeWorkouts([hike, indoor]), api);
    expect(find.text('Wanderung, 20.09.2026'), findsOneWidget);
    expect(find.text('9.3 km · 3 h 5 min · Apple Watch'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byKey(const Key('workout-w1')), matching: find.text('Importieren')));
    await settle(tester);
    expect(find.text('Importiert – in «Meine Routen»'), findsOneWidget);
    expect(bodies.single['id'], 'watch-w1');
    expect(bodies.single['title'], 'Wanderung, 20.09.2026');
    expect((bodies.single['points'] as List).length, 3, reason: 'without the inaccurate position');
    expect(
      find.descendant(of: find.byKey(const Key('workout-w1')), matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );

    // Remembered when the screen is opened again.
    await pump(tester, FakeWorkouts([hike]), api);
    expect(find.byIcon(Icons.check), findsOneWidget);

    // A workout without a track is not sent.
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).clearSnackBars();
    await pump(tester, FakeWorkouts([indoor]), api);
    await tester.tap(find.text('Importieren'));
    await settle(tester);
    expect(find.text('Dieses Training hat keine GPS-Strecke.'), findsOneWidget);
    expect(bodies, hasLength(1));
  });

  testWidgets('explains when there is nothing or no Apple Health', (tester) async {
    final api = Api('https://alvyo.test', token: 't', client: MockClient((_) async => http.Response('', 500)));
    await pump(tester, FakeWorkouts([]), api);
    expect(find.textContaining('Keine Wanderungen der letzten 60 Tage'), findsOneWidget);
    await pump(tester, FakeWorkouts([], available: false), api);
    expect(find.text('Apple Health ist auf diesem Gerät nicht verfügbar.'), findsOneWidget);
  });
}
