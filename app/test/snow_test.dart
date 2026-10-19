import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maplibre/maplibre.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/snow.dart';

Map<String, dynamic> _cover({String? date = '2026-10-18'}) => {
  'date': ?date,
  if (date != null) 'tiles': '/api/v1/weather/snow/$date/{z}/{x}/{y}/tile.png',
  'minzoom': 6,
  'maxzoom': 11,
  'bounds': {'west': 5.76, 'south': 45.68, 'east': 10.7, 'north': 47.95},
  'legend': [
    {'from': 15, 'color': '#c6dbef'},
    {'from': 50, 'color': '#6baed6'},
    {'from': 90, 'color': '#2171b5'},
  ],
  'attribution': "Generated using European Union's Copernicus Land Monitoring Service information",
};

/// Records what is done to the map's style.
class _Style implements StyleController {
  final calls = <String>[];

  @override
  dynamic noSuchMethod(Invocation i) {
    final arg = i.positionalArguments.firstOrNull;
    final what = switch (arg) {
      RasterSource(:final id, :final tiles) => 'source $id ${tiles?.single}',
      RasterStyleLayer(:final id, :final sourceId) => '$id on $sourceId below ${i.namedArguments[#belowLayerId]}',
      final String id => id,
      _ => '',
    };
    calls.add('${i.memberName.toString().split('"')[1]} $what');
    return Future<void>.value();
  }
}

SnowController _controller(ValueNotifier<Set<String>> overlays, Map<String, dynamic> cover) => SnowController(
  Api(
    'https://alvyo.test',
    client: MockClient(
      (req) async => http.Response(jsonEncode(cover), 200, headers: {'content-type': 'application/json'}),
    ),
  ),
  overlays,
);

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('de'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  test('the day\'s tiles below the places while on; switched off, they go', () async {
    final overlays = ValueNotifier<Set<String>>({});
    final c = _controller(overlays, _cover());
    final style = _Style();
    c.attach(style, below: 'places');
    expect(style.calls, isEmpty);

    overlays.value = {'snow'};
    await pumpEventQueue();
    expect(style.calls, [
      'addSource source snow https://alvyo.test/api/v1/weather/snow/2026-10-18/{z}/{x}/{y}/tile.png',
      'addLayer snow on snow below places',
    ]);

    style.calls.clear();
    overlays.value = {};
    await pumpEventQueue();
    expect(style.calls, ['removeLayer snow', 'removeSource snow']);
    c.dispose();
  });

  testWidgets('the bar: the day and the legend; nothing while off', (tester) async {
    final overlays = ValueNotifier<Set<String>>({});
    final c = _controller(overlays, _cover());
    await tester.pumpWidget(_app(SnowBar(controller: c)));
    expect(find.byKey(const Key('snow')), findsNothing);

    overlays.value = {'snow'};
    await tester.pumpAndSettle();
    expect(find.text('Schneebedeckung am 18. Oktober'), findsOneWidget);
    expect(find.textContaining('Copernicus (EU)'), findsOneWidget);
    c.dispose();
  });

  testWidgets('no day yet: says so, draws nothing', (tester) async {
    final overlays = ValueNotifier<Set<String>>({'snow'});
    final c = _controller(overlays, _cover(date: null));
    final style = _Style();
    c.attach(style, below: 'places');
    await tester.pumpWidget(_app(SnowBar(controller: c)));
    await tester.pumpAndSettle();
    expect(find.text('Noch keine Schneedaten.'), findsOneWidget);
    expect(style.calls, isEmpty);
    c.dispose();
  });
}
