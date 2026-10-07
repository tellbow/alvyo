import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:maplibre/maplibre.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/precip.dart';

final _now = DateTime.now().toUtc();

Map<String, dynamic> _frame(String kind, Duration from) {
  final t = _now.add(from);
  return {
    'kind': kind,
    'time': t.toIso8601String(),
    'url': '/api/v1/weather/precip/$kind/${t.millisecondsSinceEpoch ~/ 1000}/frame.png?v=1',
  };
}

final _timeline = {
  'bounds': {'west': 2.689, 'south': 43.619, 'east': 12.462, 'north': 49.374},
  'frames': [
    _frame('radar', const Duration(minutes: -10)),
    _frame('radar', const Duration(minutes: -5)),
    _frame('forecast', const Duration(hours: 1)),
  ],
  'legend': [
    {'from': 0.1, 'color': '#a6dbf7'},
    {'from': 40, 'color': '#96005a'},
  ],
  'attribution': 'MeteoSchweiz',
};

/// Records what is done to the map's style.
class _Style implements StyleController {
  final calls = <String>[];

  @override
  dynamic noSuchMethod(Invocation i) {
    final arg = i.positionalArguments.firstOrNull;
    final what = switch (arg) {
      ImageSource(:final id) => 'source $id',
      RasterStyleLayer(:final id, :final sourceId) => '$id on $sourceId below ${i.namedArguments[#belowLayerId]}',
      final String id => id,
      _ => '',
    };
    calls.add('${i.memberName.toString().split('"')[1]} $what');
    return Future<void>.value();
  }
}

PrecipController _controller(ValueNotifier<Set<String>> overlays) => PrecipController(
  Api(
    'https://alvyo.test',
    client: MockClient(
      (req) async => http.Response(jsonEncode(_timeline), 200, headers: {'content-type': 'application/json'}),
    ),
  ),
  overlays,
);

void main() {
  test('times: radar at its minute, a forecast hour as a span, another day with its weekday', () async {
    await initializeDateFormatting('de');
    final at = DateTime(2026, 10, 7, 9, 45);
    expect(
      precipTime(PrecipFrame.fromJson({'kind': 'radar', 'time': at.toIso8601String(), 'url': ''}), 'de', now: at),
      '09:45',
    );
    expect(
      precipTime(
        PrecipFrame.fromJson({'kind': 'forecast', 'time': DateTime(2026, 10, 7, 11).toIso8601String(), 'url': ''}),
        'de',
        now: at,
      ),
      '10:00–11:00',
    );
    expect(
      precipTime(
        PrecipFrame.fromJson({'kind': 'forecast', 'time': DateTime(2026, 10, 8, 1).toIso8601String(), 'url': ''}),
        'de',
        now: at,
      ),
      'Do 00:00–01:00',
    );
  });

  test('the timeline starts at the newest radar picture', () {
    final t = PrecipTimeline.fromJson(_timeline);
    expect(t.frames.map((f) => f.kind), ['radar', 'radar', 'forecast']);
    expect(t.now, 1);
    expect(t.legend.first, const Color(0xffa6dbf7));
  });

  test('one layer moves from picture to picture below the places; switched off, all go', () async {
    final overlays = ValueNotifier<Set<String>>({});
    final c = _controller(overlays);
    final style = _Style();
    c.attach(style, below: 'places');
    expect(style.calls, isEmpty);

    overlays.value = {'precip'};
    await pumpEventQueue();
    final ids = [for (final f in c.timeline.value!.frames) 'precip-${f.url.hashCode}'];
    expect(style.calls, ['addSource source ${ids[1]}', 'addLayer precip on ${ids[1]} below places']);

    style.calls.clear();
    c.index.value = 2;
    await pumpEventQueue();
    expect(style.calls, [
      'addSource source ${ids[2]}',
      'removeLayer precip',
      'addLayer precip on ${ids[2]} below places',
    ]);

    style.calls.clear();
    overlays.value = {};
    await pumpEventQueue();
    expect(style.calls, ['removeLayer precip', 'removeSource ${ids[1]}', 'removeSource ${ids[2]}']);
    c.dispose();
  });

  testWidgets('the bar: the time, measured or forecast, and nothing while off', (tester) async {
    final overlays = ValueNotifier<Set<String>>({});
    final c = _controller(overlays);
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
        home: Scaffold(body: PrecipBar(controller: c)),
      ),
    );
    expect(find.byKey(const Key('precip')), findsNothing);

    overlays.value = {'precip'};
    await tester.pumpAndSettle();
    expect(find.text('Radar, gemessen'), findsOneWidget);
    expect(find.textContaining('MeteoSchweiz'), findsOneWidget);

    c.index.value = 2;
    await tester.pumpAndSettle();
    expect(find.text('Modellprognose'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('precip-time'))).data, matches(RegExp(r'^\d\d:\d\d–\d\d:\d\d$')));

    overlays.value = {};
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('precip')), findsNothing);
    c.dispose();
  });
}
