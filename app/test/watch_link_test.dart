import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/navigation/recording.dart';
import 'package:alvyo/navigation/tracker.dart';
import 'package:alvyo/navigation/watch.dart';
import 'package:alvyo/screens/navigate_screen.dart';
import 'package:alvyo/screens/record_screen.dart';

const _channel = MethodChannel('test/watch');
final _messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// What the phone sent to the watch.
final _sent = <MethodCall>[];

/// A button pressed on the watch; the phone's answer.
Future<Object?> _press(String method, [Object? args]) async {
  final reply = Completer<Object?>();
  await _messenger.handlePlatformMessage(
    _channel.name,
    _channel.codec.encodeMethodCall(MethodCall(method, args)),
    (data) => reply.complete(data == null ? null : _channel.codec.decodeEnvelope(data)),
  );
  return reply.future;
}

Map<Object?, Object?>? _lastHike() => _sent.lastWhere((c) => c.method == 'hike').arguments as Map<Object?, Object?>?;

Fix _fix(int i) => Fix(
  lon: 8,
  lat: 46.5 + i * 0.0005,
  accuracyM: 5,
  time: DateTime.utc(2026, 10, 25, 8).add(Duration(minutes: i)),
);

void main() {
  setUp(() {
    _sent.clear();
    _messenger.setMockMethodCallHandler(_channel, (call) async {
      _sent.add(call);
      return null;
    });
  });
  tearDown(() => _messenger.setMockMethodCallHandler(_channel, null));

  test('the watch\'s buttons act on the hike shown, and a start goes to the home screen', () async {
    final link = WatchLink(channel: _channel, enabled: true);
    expect(await _press('start', {'title': 'Napf'}), 'notReady', reason: 'logged out');
    expect(await _press('pause'), 'none', reason: 'no hike');

    final started = <(String?, String)>[];
    link.onStart = (id, title) async => started.add((id, title));
    expect(await _press('start', {'routeId': 'r1', 'title': 'Napf'}), 'ok');
    expect(await _press('start', {'title': ''}), 'ok');
    expect(started, [('r1', 'Napf'), (null, '')]);

    final pressed = <String>[];
    link.controls = HikeControls(
      pause: () async => pressed.add('pause'),
      resume: () async => pressed.add('resume'),
      stop: () async => pressed.add('stop'),
    );
    expect(await _press('start', {'title': ''}), 'busy', reason: 'a hike is on already');
    for (final b in ['pause', 'resume', 'stop']) {
      expect(await _press(b), 'ok');
    }
    expect(pressed, ['pause', 'resume', 'stop']);
  });

  test('a start asked for while the phone was locked is done once the app is open', () async {
    final link = WatchLink(channel: _channel, enabled: true);
    final started = <(String?, String)>[];
    link.onStart = (id, title) async => started.add((id, title));
    _messenger.setMockMethodCallHandler(
      _channel,
      (call) async => call.method == 'pendingStart' ? {'routeId': 'r1', 'title': 'Napf'} : null,
    );
    await link.startPending();
    await Future<void>.delayed(Duration.zero);
    expect(started, [('r1', 'Napf')]);
  });

  test('lines for the watch are cut down, keeping their ends and shape', () {
    // 3000 points along a zigzag, 1 km apart at the corners.
    final line = [
      for (var i = 0; i < 3000; i++) [8 + i * 0.00001, 46.5 + 0.009 * (sin(i / 3000 * 4 * pi)).abs(), 500.0],
    ];
    final short = simplifyLine(line, 300);
    expect(short.length, lessThanOrEqualTo(300));
    expect(short.length, greaterThan(10));
    expect(short.first, line.first);
    expect(short.last, line.last);
    expect(simplifyLine(line.take(5).toList(), 300), hasLength(5));
  });

  testWidgets('Aufzeichnen from the watch: started, paused, stopped there; the phone shows the same', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = Directory.systemTemp.createTempSync('recordings');
    addTearDown(() => root.deleteSync(recursive: true));
    final link = WatchLink(channel: _channel, enabled: true);
    final api = Api('https://alvyo.test', token: 't', client: MockClient((_) async => http.Response('', 404)));
    final positions = StreamController<Fix>();
    addTearDown(positions.close);
    HikeSummary? summary;
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
            onPressed: () async => summary = await Navigator.of(context).push<HikeSummary>(
              MaterialPageRoute(
                builder: (_) => RecordScreen(
                  api: api,
                  start: true,
                  positions: () => positions.stream,
                  recordings: root,
                  map: const SizedBox.expand(),
                  watch: link,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // File work: real time. The watch's buttons are not awaited: the
    // recording's writes finish in the test's zone, during settle.
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await settle();
    expect(find.byKey(const Key('record-progress')), findsOneWidget, reason: 'started without a tap');
    expect(link.controls, isNotNull);
    expect(_lastHike()?['title'], 'Wanderung');

    positions.add(_fix(0));
    await settle();
    positions.add(_fix(1));
    await settle();
    expect(_lastHike()?['doneM'], closeTo(55.7, 1));
    expect((_lastHike()?['line'] as List).length, 4, reason: 'two points, lon and lat');

    unawaited(_press('pause'));
    await settle();
    expect(find.byKey(const Key('nav-paused')), findsOneWidget);
    expect(_lastHike()?['paused'], isTrue);
    positions.add(_fix(2)); // to the restaurant: not recorded
    await settle();
    expect(_lastHike()?['doneM'], closeTo(55.7, 1));

    unawaited(_press('resume'));
    await settle();
    expect(find.byKey(const Key('nav-paused')), findsNothing);
    positions.add(_fix(3));
    await settle();

    // Asked on the watch: no question on the phone.
    unawaited(_press('stop'));
    await settle();
    expect(find.byKey(const Key('nav-finish-confirm')), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(summary, isNotNull);
    expect(_sent.last.method, 'hike');
    expect(_sent.last.arguments, isNull, reason: 'the watch shows the hike no more');
    expect(link.controls, isNull);
    expect(await tester.runAsync(() => Recording.active(root)), isNull);
  });
}
