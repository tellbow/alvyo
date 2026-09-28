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
import 'package:alvyo/screens/route_screen.dart';

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

  // Sargans – Weisstannen crosses several wildlife rest areas: on an iPhone
  // the list under the map scrolls, the map keeps its place, and the
  // keyboard of the dialog before (still closing) takes no room.
  testWidgets('many protected areas and the keyboard: the panel scrolls, nothing overflows', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(tester.view.reset);
    final client = MockClient((req) async {
      switch (req.url.path) {
        case '/api/v1/routes/r1':
          return _json({
            'id': 'r1',
            'title': 'Sargans – Weisstannen',
            'owner_username': 'wodan',
            'profile': 'hike',
            'totals': {
              'distance_m': 16600.0,
              'ascent_m': 1121.0,
              'descent_m': 600.0,
              'duration_s': 19780,
              'sac_grade': 2,
              'sac_max': 2,
            },
            'legs': [
              {
                'coordinates': [
                  for (var i = 0; i < 50; i++) [9.44 - i * 0.002, 47.04 - i * 0.001, 500.0 + i * 20],
                ],
              },
            ],
          });
        case '/api/v1/routes/r1/areas':
          return _json({
            'areas': [
              for (var i = 0; i < 8; i++)
                {
                  'kind': 'wildlife_rest',
                  'name': 'Wildruhezone Nummer $i',
                  'binding': true,
                  'rule': {'de': 'Zutrittsverbot'},
                  'period': {'from': '12-20', 'to': '04-30'},
                },
            ],
          });
      }
      return http.Response('', 404);
    });
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
        home: RouteScreen(
          api: Api('http://test', token: 't', client: client),
          id: 'r1',
          title: 'Sargans – Weisstannen',
          map: const SizedBox.expand(key: Key('map')),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Wildruhezone Nummer 0'), findsOneWidget);
    // The map keeps at least half of what is left above the keyboard.
    expect(tester.getSize(find.byKey(const Key('map'))).height, greaterThan(150));
    expect(tester.takeException(), isNull);
    // The buttons are reached by scrolling the panel.
    await tester.scrollUntilVisible(find.byKey(const Key('nav-start')), 100);
    expect(find.byKey(const Key('nav-start')), findsOneWidget);
  });

  // Someone else's recorded hike of 600 m: the server leaves out its start
  // and end, which is all of it.
  testWidgets("someone else's short hike: no line, a note, nothing to start", (tester) async {
    final client = MockClient((req) async {
      if (req.url.path == '/api/v1/routes/r1') {
        return _json({
          'id': 'r1',
          'title': 'Wanderung, 28.09.2026',
          'owner_username': 'anna',
          'profile': 'hike',
          'can_edit': false,
          'role': 'viewer',
          'hike': {'at': '2026-09-28T08:00:00Z', 'duration_s': 600},
          'totals': {
            'distance_m': 600.0,
            'ascent_m': 0.0,
            'descent_m': 0.0,
            'duration_s': 480,
            'sac_grade': 1,
            'sac_max': 1,
          },
          'anchors': [],
          'legs': [],
        });
      }
      return http.Response('', 404);
    });
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
        home: RouteScreen(
          api: Api('http://test', token: 't', client: client),
          id: 'r1',
          title: 'Wanderung',
          map: const SizedBox.expand(),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.text('Diese Wanderung ist zu kurz, um sie anderen zu zeigen: Start und Ende sind verborgen.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('nav-start')), findsNothing);
    expect(find.byKey(const Key('offline-save')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // A route of one's own is deleted from its menu, after asking; a stage's
  // route is deleted with its stage.
  for (final (role, journey, menu) in [('owner', null, true), ('editor', null, false), ('owner', 'j1', false)]) {
    testWidgets('delete as $role${journey == null ? '' : ' of a stage'}', (tester) async {
      var deleted = false;
      final client = MockClient((req) async {
        switch ((req.method, req.url.path)) {
          case ('DELETE', '/api/v1/routes/r1'):
            deleted = true;
            return http.Response('', 204);
          case ('GET', '/api/v1/routes/r1'):
            return _json({
              'id': 'r1',
              'title': 'Rundweg',
              'owner_username': 'wodan',
              'role': role,
              'journey_id': journey,
              'profile': 'hike',
              'totals': {
                'distance_m': 1000.0,
                'ascent_m': 10.0,
                'descent_m': 10.0,
                'duration_s': 900,
                'sac_grade': 1,
                'sac_max': 1,
              },
              'legs': [
                {
                  'coordinates': [
                    [9.44, 47.04, 500.0],
                    [9.45, 47.04, 510.0],
                  ],
                },
              ],
            });
        }
        return _json({'areas': <Object>[]});
      });
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
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RouteScreen(
                    api: Api('http://test', token: 't', client: client),
                    id: 'r1',
                    title: 'Rundweg',
                    map: const SizedBox.expand(),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      // The screen's spinner never settles: pumped a while instead.
      Future<void> settle() async {
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.tap(find.text('open'));
      await settle();
      // The menu has more (GPX, editing …); «Löschen» only for the owner.
      await tester.tap(find.byKey(const Key('item-menu')));
      await settle();
      expect(find.byKey(const Key('item-delete')), menu ? findsOneWidget : findsNothing);
      if (!menu) return;
      await tester.tap(find.byKey(const Key('item-delete')));
      await settle();
      expect(find.text('Route löschen? Das lässt sich nicht rückgängig machen.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('delete-confirm')));
      await settle();
      expect(deleted, isTrue);
      expect(find.byType(RouteScreen), findsNothing, reason: 'left after deleting');
    });
  }
}
