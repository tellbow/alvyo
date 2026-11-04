import 'dart:convert';

import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/route_layers.dart';
import 'package:alvyo/screens/canton_map.dart';
import 'package:alvyo/screens/hike_done_screen.dart';
import 'package:alvyo/screens/navigate_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maplibre/maplibre.dart' show MapEventIdle;

void main() {
  group('lineUpTo', () {
    final line = [
      [8.0, 47.0, 500.0],
      [8.0, 47.1, 600.0],
      [8.0, 47.3, 700.0],
    ];

    test('goes by length, not by point', () {
      final half = lineUpTo(line, 0.5);
      expect(half, hasLength(3));
      expect(half.last[1], closeTo(47.15, 1e-9));
    });

    test('nothing yet is one point, the end the whole line', () {
      expect(lineUpTo(line, 0), hasLength(2));
      expect(lineUpTo(line, 0)[1][1], closeTo(47.0, 1e-9));
      expect(lineUpTo(line, 1), same(line));
    });

    test('points on the same spot do no harm', () {
      final still = [
        [8.0, 47.0],
        [8.0, 47.0],
      ];
      expect(lineUpTo(still, 0.5).last, [8.0, 47.0]);
    });
  });

  group('WhenTilesIn', () {
    testWidgets('once, at the first idle map or else after the wait', (tester) async {
      var calls = 0;
      final idle = WhenTilesIn(() => calls++);
      idle.onEvent(const MapEventIdle());
      expect(calls, 0, reason: 'not armed yet: another map\'s tiles');
      idle.arm();
      idle.onEvent(const MapEventIdle());
      idle.onEvent(const MapEventIdle());
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(calls, 1);

      calls = 0;
      final late = WhenTilesIn(() => calls++)..arm();
      await tester.pump(const Duration(seconds: 2));
      expect(calls, 1, reason: 'no signal: not forever');
      late.dispose();
    });

    testWidgets('not after dispose', (tester) async {
      var calls = 0;
      WhenTilesIn(() => calls++)
        ..arm()
        ..dispose();
      await tester.pump(const Duration(seconds: 2));
      expect(calls, 0);
    });
  });

  group('SeenCantons', () {
    test('the first look only notes them, then what is new', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final seen = SeenCantons();
      expect(await seen.fresh(['BE']), isEmpty);
      expect(await seen.fresh(['BE']), isEmpty);
      expect(await seen.fresh(['BE', 'VS']), ['VS']);
      expect(await seen.fresh(['VS']), isEmpty);
      expect(await seen.fresh(['BE', 'VS']), isEmpty, reason: 'a deleted hike does not make it new again');
    });

    test('no canton yet: the first one counts as new', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final seen = SeenCantons();
      expect(await seen.fresh([]), isEmpty);
      expect(await seen.fresh(['UR']), ['UR']);
    });
  });

  group('the end of a hike', () {
    const summary = HikeSummary(12300, Duration(hours: 3, minutes: 30), 'h1', [
      [8.0, 47.0],
      [8.1, 47.1],
    ]);
    late List<String> haptics;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({SeenCantons.key: 'BE'});
      haptics = [];
    });

    Future<void> pump(
      WidgetTester tester, {
      List<String> cantons = const ['BE'],
      bool disableAnimations = false,
      Future<void>? uploaded,
    }) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final client = MockClient(
        (req) async => http.Response(
          jsonEncode({'cantons': cantons, 'cantons_total': 26, 'official': [], 'summits': [], 'huts': []}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
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
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: HikeDoneScreen(
              api: Api('http://test', token: 't', client: client),
              summary: summary,
              uploaded: uploaded ?? Future<void>.value(),
              map: const SizedBox.expand(),
            ),
          ),
        ),
      );
    }

    testWidgets('the numbers count up, once, with a tap at the end', (tester) async {
      await pump(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('12.3 km'), findsNothing);
      expect(haptics, isEmpty);
      await tester.pumpAndSettle();
      expect(find.text('12.3 km'), findsOneWidget);
      expect(haptics, ['HapticFeedbackType.lightImpact']);
    });

    testWidgets('a touch skips it', (tester) async {
      await pump(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Geschafft'));
      await tester.pump();
      expect(find.text('12.3 km'), findsOneWidget);
    });

    testWidgets('less motion: at the end at once', (tester) async {
      await pump(tester, disableAnimations: true);
      await tester.pump();
      expect(find.text('12.3 km'), findsOneWidget);
    });

    testWidgets('a new canton shows once the hike is uploaded', (tester) async {
      await pump(tester, cantons: ['BE', 'VS']);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      expect(find.text('Neu dabei: VS'), findsOneWidget);
      expect(find.byKey(const Key('canton-map')), findsOneWidget);
    });

    testWidgets('no new canton: no map', (tester) async {
      await pump(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hike-done-canton')), findsNothing);
      expect(find.byKey(const Key('canton-map')), findsNothing);
    });

    testWidgets('a hike without a line skips the screen', (tester) async {
      var pushed = false;
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [_Pushed(() => pushed = true)],
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showHikeDone(
                Navigator.of(context),
                Api('http://test', token: 't', client: MockClient((_) async => http.Response('', 500))),
                const HikeSummary(0, Duration.zero, 'h2'),
                Future<void>.value(),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      pushed = false;
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(pushed, isFalse);
    });
  });

  testWidgets('the canton map paints from its asset', (tester) async {
    rootBundle.evict('assets/cantons.json'); // cached by an earlier test's clock, which stopped
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('de'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CantonMap(walked: ['BE', 'AI'], fresh: ['AI']),
        ),
      ),
    );
    CustomPainter? painter() => tester.widget<CustomPaint>(find.byKey(const Key('canton-map'))).painter;
    for (var i = 0; i < 50 && painter() == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(painter(), isNotNull);
    expect(find.text('© swisstopo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Pushed extends NavigatorObserver {
  _Pushed(this.onPush);
  final VoidCallback onPush;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => onPush();
}
