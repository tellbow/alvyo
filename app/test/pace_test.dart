import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/format.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/screens/tiles.dart';

void main() {
  tearDown(() => hikerPace.value = 1);

  test('the account tells the hiker\'s pace', () async {
    final api = Api(
      'https://alvyo.test',
      token: 't',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'id': 'u1', 'username': 'wodan', 'display_name': 'Wodan', 'speed_factor': 1.2}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    await api.me();
    expect(hikerPace.value, 1.2);
  });

  testWidgets('a route\'s time at the hiker\'s pace, as on the website', (tester) async {
    hikerPace.value = 1.2;
    final route = RouteSummary.fromJson({
      'id': 'r1',
      'title': 'Sargans – Weisstannen',
      'owner_username': 'wodan',
      'totals': {
        'distance_m': 12600,
        'ascent_m': 900,
        'descent_m': 381,
        'duration_s': 15485, // 4 h 20 min
        'sac_grade': 2,
        'sac_max': 3,
      },
      'tags': <String>[],
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
        home: Scaffold(
          body: RouteTile(route: route, onTap: () {}),
        ),
      ),
    );
    expect(find.textContaining('5 h 10 min'), findsOneWidget);
  });
}
