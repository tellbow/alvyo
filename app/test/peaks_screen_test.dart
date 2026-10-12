import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/peaks/pack.dart';
import 'package:alvyo/peaks/projection.dart';
import 'package:alvyo/peaks/store.dart';
import 'package:alvyo/screens/peaks_screen.dart';

import 'peaks_fixture.dart';

// Upright, the camera to the north.
const _north = CameraPose([0, -1, 0, 0, 0, 1, -1, 0, 0], fov: 60);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('peaks'));
  tearDown(() => dir.deleteSync(recursive: true));

  final bytes = peakPackBytes(500, 500, (lon, lat) => 500, const [Summit('Gipfel', 2500, 7.5, 47.1)]);

  Widget app(Api api, {Stream<CameraPose>? motion, Future<({double lon, double lat})?> Function()? position}) =>
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: PeaksScreen(
          api: api,
          store: Future.value(PeakStore(File('${dir.path}/peaks.bin.gz'))),
          position: position ?? () async => (lon: 7.5, lat: 46.95),
          motion: motion ?? Stream.value(_north),
          camera: const ColoredBox(color: Colors.black),
        ),
      );

  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  testWidgets('downloaded once (asked again while the server builds it), then the view', (tester) async {
    var asked = 0;
    final api = Api(
      'https://alvyo.test',
      client: MockClient((req) async {
        expect(req.url.path, '/api/v1/peaks/pack');
        return ++asked == 1 ? http.Response('', 503) : http.Response.bytes(bytes, 200);
      }),
    );
    await tester.pumpWidget(app(api));
    await settle(tester, () => find.byKey(const Key('peaks-download-start')).evaluate().isNotEmpty);
    expect(find.textContaining('etwa 9 MB'), findsOneWidget);

    // The store waits 10 s between asking; in the test, the second answer
    // comes after that wait, so the store is driven directly.
    final store = PeakStore(File('${dir.path}/peaks.bin.gz'));
    await tester.runAsync(() => store.download(api, wait: Duration.zero));
    expect(asked, 2);
    expect(store.saved, isTrue);

    await tester.pumpWidget(const SizedBox()); // a new screen
    await tester.pumpWidget(app(api));
    await settle(tester, () => find.byKey(const Key('peaks-overlay')).evaluate().isNotEmpty);
    expect(find.byKey(const Key('peaks-overlay')), findsOneWidget);
    expect(find.text('Richtung 0° · Neigung 0°'), findsOneWidget);
    expect(find.byKey(const Key('peaks-message')), findsNothing);
    // The pack's sources: Mapterhorn's terrain, OpenStreetMap's summits.
    expect(find.text('Gelände: Mapterhorn · Gipfel: © OpenStreetMap-Mitwirkende'), findsOneWidget);
  });

  testWidgets('dragging aligns the view; reset undoes it', (tester) async {
    File('${dir.path}/peaks.bin.gz').writeAsBytesSync(bytes);
    await tester.pumpWidget(app(Api('https://alvyo.test')));
    await settle(tester, () => find.byKey(const Key('peaks-overlay')).evaluate().isNotEmpty);
    await tester.drag(find.byKey(const Key('peaks-overlay')), const Offset(100, 0));
    await tester.pump();
    expect(find.text('Richtung 0° · Neigung 0°'), findsNothing);
    await tester.tap(find.byKey(const Key('peaks-reset')));
    await tester.pump();
    expect(find.text('Richtung 0° · Neigung 0°'), findsOneWidget);
    expect(find.byKey(const Key('peaks-reset')), findsNothing);
  });

  testWidgets('without a position or a compass it says so', (tester) async {
    File('${dir.path}/peaks.bin.gz').writeAsBytesSync(bytes);
    await tester.pumpWidget(app(Api('https://alvyo.test'), position: () async => null));
    await settle(tester, () => find.textContaining('Standort').evaluate().isNotEmpty);
    expect(find.textContaining('erlaube den Standort'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(Api('https://alvyo.test'), motion: Stream.error(Exception('no compass'))));
    await settle(tester, () => find.textContaining('Kompass').evaluate().isNotEmpty);
    expect(find.text('Dieses Gerät hat keinen Kompass.'), findsOneWidget);
  });
}
