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
import 'package:alvyo/screens/discover_screen.dart';
import 'package:alvyo/screens/journey_screen.dart';
import 'package:alvyo/screens/route_screen.dart';

const _view = (west: 7.0, south: 46.0, east: 8.0, north: 47.0);

Map<String, dynamic> _item(String kind, String id, String title, {int stages = 0}) => {
  'kind': kind,
  'id': id,
  'title': title,
  'owner_username': 'anna',
  'distance_m': 12400.0,
  'ascent_m': 812.4,
  'duration_s': 3600,
  'longest_s': kind == 'journey' ? 7200 : 3600,
  'sac_grade': 2,
  'sac_max': 3,
  'stages': stages,
  'lines': [
    [
      [7.5, 46.5],
      [7.6, 46.6],
    ],
  ],
};

/// The server: the hiker walks at 1.25 times the Swiss hiking time; the
/// discover answers are [items], or none while [offline].
class _Server {
  var offline = false;
  var items = [_item('route', 'r1', 'Über den Hohtürli'), _item('journey', 'j1', 'Via Alpina', stages: 2)];
  var more = false;
  final asked = <Uri>[];

  /// While set, discover answers wait for it.
  Completer<void>? hold;

  late final client = MockClient((req) async {
    final p = req.url.path.replaceFirst('/api/v1', '');
    if (p == '/me') {
      return _json({'id': 'u1', 'username': 'me', 'display_name': 'Me', 'speed_factor': 1.25});
    }
    if (p == '/discover') {
      asked.add(req.url);
      final answer = {'items': items, 'more': more};
      await hold?.future;
      if (offline) throw const SocketException('no connection');
      return _json(answer);
    }
    return http.Response('', 404);
  });

  http.Response _json(Object body) =>
      http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
}

/// Stands in for the map: reports a view at once and opens items by key.
class _FakeMap extends StatefulWidget {
  const _FakeMap(this.items, this.onView, this.onOpen);
  final List<DiscoverItem> items;
  final ValueChanged<Bbox> onView;
  final ValueChanged<DiscoverItem> onOpen;

  @override
  State<_FakeMap> createState() => _FakeMapState();
}

class _FakeMapState extends State<_FakeMap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onView(_view));
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final it in widget.items)
        TextButton(key: Key('line-${it.id}'), onPressed: () => widget.onOpen(it), child: Text('line ${it.id}')),
    ],
  );
}

Future<void> _pump(WidgetTester tester, _Server server) async {
  // Tall enough for the list; the filters scroll sideways as on a phone.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
      home: DiscoverScreen(
        api: Api('http://test', token: 't', client: server.client),
        map: (items, onView, onOpen) => _FakeMap(items, onView, onOpen),
      ),
    ),
  );
  await tester.pump(); // the view is reported
  await tester.pump(const Duration(milliseconds: 300)); // after the camera rests
  await tester.pump();
}

/// Lets menus and pages move in while something keeps spinning.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  // The route and journey screens keep files in a temporary directory.
  late Directory support;
  setUpAll(() {
    support = Directory.systemTemp.createTempSync('support');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => support.path,
    );
  });
  tearDownAll(() => support.deleteSync(recursive: true));

  testWidgets('the public hikes in view, with times at the hiker\'s pace', (tester) async {
    final server = _Server()..more = true;
    await _pump(tester, server);

    expect(server.asked, hasLength(1));
    expect(server.asked.single.queryParameters, {'bbox': '7.0000,46.0000,8.0000,47.0000'});
    expect(find.text('Über den Hohtürli'), findsOneWidget);
    expect(find.text('Via Alpina'), findsOneWidget);
    expect(find.byKey(const Key('line-r1')), findsOneWidget);
    // 1 h Swiss hiking time is 1 h 15 min at 1.25.
    expect(
      find.text('Route · von anna\n12.4\u00a0km · 1\u00a0h 15\u00a0min · ↑\u00a0812\u00a0m · T2–T3'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Etappentour · von anna\n12.4\u00a0km · 1\u00a0h 15\u00a0min · ↑\u00a0812\u00a0m · T2–T3\n2 Etappen · längste 2\u00a0h 30\u00a0min',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('discover-more')), findsOneWidget);

    server.items = [];
    server.more = false;
    await tester.tap(find.byKey(const Key('discover-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discover-kind-journey')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('discover-empty')), findsOneWidget);
  });

  testWidgets('the filters are sent, hours as Swiss hiking time', (tester) async {
    final server = _Server();
    await _pump(tester, server);

    Future<void> choose(String menu, String value) async {
      await tester.ensureVisible(find.byKey(Key('discover-$menu')));
      await tester.tap(find.byKey(Key('discover-$menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('discover-$menu-$value')).last);
      await tester.pumpAndSettle();
    }

    await choose('kind', 'route');
    await choose('hours', 'medium');
    expect(find.text('2–4 h'), findsOneWidget);
    expect(find.text('Bei Etappentouren zählt die längste Etappe.'), findsNothing); // routes only
    await choose('sac', '3');
    expect(find.text('bis T3'), findsOneWidget);

    expect(server.asked, hasLength(4));
    // 2 and 4 hours at 1.25 times the Swiss time.
    expect(server.asked.last.queryParameters, {
      'bbox': '7.0000,46.0000,8.0000,47.0000',
      'kind': 'route',
      'sac_max': '3',
      'duration_min': '5760',
      'duration_max': '11520',
    });

    await choose('kind', '');
    expect(find.text('Bei Etappentouren zählt die längste Etappe.'), findsOneWidget);
    expect(server.asked.last.queryParameters.containsKey('kind'), isFalse);
  });

  testWidgets('an answer overtaken by a newer search is dropped', (tester) async {
    final server = _Server();
    await _pump(tester, server);

    server.hold = Completer();
    await tester.ensureVisible(find.byKey(const Key('discover-sac')));
    await tester.tap(find.byKey(const Key('discover-sac')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('discover-sac-2')).last);
    await _settle(tester);
    final first = server.hold!;
    server.hold = null;
    server.items = [_item('route', 'r2', 'Newer')];
    await tester.ensureVisible(find.byKey(const Key('discover-sac')));
    await tester.tap(find.byKey(const Key('discover-sac')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('discover-sac-3')).last);
    await _settle(tester);
    expect(find.text('Newer'), findsOneWidget);

    first.complete(); // the older answer, with the older items
    await _settle(tester);
    expect(find.text('Newer'), findsOneWidget);
    expect(find.text('Via Alpina'), findsNothing);
  });

  testWidgets('a route opens in the route screen, a journey in the journey screen', (tester) async {
    final server = _Server();
    await _pump(tester, server);

    await tester.tap(find.text('Über den Hohtürli'));
    await _settle(tester);
    final route = tester.widget<RouteScreen>(find.byType(RouteScreen));
    expect((route.id, route.title), ('r1', 'Über den Hohtürli'));
    await tester.tap(find.byType(BackButton));
    await _settle(tester);

    await tester.tap(find.byKey(const Key('line-j1'))); // a line on the map
    await _settle(tester);
    final journey = tester.widget<JourneyScreen>(find.byType(JourneyScreen));
    expect((journey.id, journey.title), ('j1', 'Via Alpina'));
  });

  testWidgets('offline: says so instead of a spinner, and tries again', (tester) async {
    final server = _Server()..offline = true;
    await _pump(tester, server);

    expect(find.byKey(const Key('discover-offline')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    server.offline = false;
    await tester.tap(find.byKey(const Key('discover-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('discover-offline')), findsNothing);
    expect(find.text('Via Alpina'), findsOneWidget);
  });

  test('others\' public routes cannot be changed; saved copies without the flag can', () {
    RouteDetail route(Map<String, dynamic> extra) => RouteDetail.fromJson({
      'id': 'r1',
      'title': 'R',
      'owner_username': 'anna',
      'totals': {'distance_m': 1.0, 'ascent_m': 0, 'descent_m': 0, 'duration_s': 60, 'sac_grade': 1, 'sac_max': 1},
      'legs': [],
      ...extra,
    });
    expect(route({'can_edit': false}).canEdit, isFalse);
    expect(route({'can_edit': true}).canEdit, isTrue);
    expect(route({}).canEdit, isTrue);
  });
}
