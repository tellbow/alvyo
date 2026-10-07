import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/navigation/tracker.dart';
import 'package:alvyo/screens/record_screen.dart';

const _totals = {
  'distance_m': 11100.0,
  'ascent_m': 742.0,
  'descent_m': 742.0,
  'duration_s': 14100,
  'sac_grade': 2,
  'sac_max': 3,
};

Map<String, dynamic> _route(String id, String title, {String? done, String owner = 'wodan'}) => {
  'id': id,
  'title': title,
  'owner_username': owner,
  'visibility': 'private',
  'totals': _totals,
  'tags': <String>[],
  'done_on': ?done,
};

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  late Directory support;
  setUpAll(() {
    support = Directory.systemTemp.createTempSync('support');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => support.path,
    );
  });
  tearDownAll(() => support.deleteSync(recursive: true));

  testWidgets('Aufzeichnen: a tour to follow, chosen among those not hiked yet and shared ones', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = Api(
      'https://alvyo.test',
      token: 't',
      client: MockClient(
        (req) async => switch (req.url.path) {
          '/api/v1/routes' => _json({
            'routes': [_route('r1', 'Napf'), _route('r2', 'Säntis', done: '2026-08-01')],
          }),
          '/api/v1/shared' => _json({
            'routes': [_route('r3', 'JaNey', owner: 'bossm8')],
            'journeys': <Object>[],
            'collections': <Object>[],
          }),
          _ => http.Response('', 404),
        },
      ),
    );
    final positions = StreamController<Fix>();
    addTearDown(positions.close);
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
        home: RecordScreen(
          api: api,
          positions: () => positions.stream,
          recordings: support,
          map: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Einer Tour folgen (optional)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('record-tour')));
    for (var i = 0; i < 20 && find.byKey(const Key('record-tour-r1')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('record-tour-r1')), findsOneWidget);
    expect(find.byKey(const Key('record-tour-r3')), findsOneWidget);
    expect(find.byKey(const Key('record-tour-r2')), findsNothing); // hiked already

    await tester.pumpAndSettle(); // the sheet open
    await tester.tap(find.byKey(const Key('record-tour-r1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('record-tour-r3')), findsNothing); // the sheet closed
    expect(find.text('Napf'), findsOneWidget);
    await tester.tap(find.byKey(const Key('record-tour-clear')));
    await tester.pump();
    expect(find.text('Napf'), findsNothing);
    expect(find.text('Tour wählen'), findsOneWidget);
  });
}
