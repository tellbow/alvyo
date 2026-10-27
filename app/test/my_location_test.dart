import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/my_location.dart';

/// The phone's location as the button sees it.
class _Geo extends GeolocatorPlatform {
  _Geo({this.on = true, this.permission = LocationPermission.whileInUse});
  final bool on;
  LocationPermission permission;
  var asked = 0;
  var settingsOpened = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => on;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    asked++;
    return permission = LocationPermission.deniedForever;
  }

  @override
  Future<Position?> getLastKnownPosition({bool forceLocationManager = false}) async => null;
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) => Future.error(TimeoutException('no fix'));
  @override
  Future<bool> openLocationSettings() async {
    settingsOpened++;
    return true;
  }
}

void main() {
  Future<void> show(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: MyLocationButton(map: () => null)),
    ),
  );

  testWidgets('location switched off: opens the settings', (tester) async {
    final geo = GeolocatorPlatform.instance = _Geo(on: false);
    await show(tester);
    await tester.tap(find.byKey(const Key('map-my-location')));
    await tester.pumpAndSettle();
    expect(geo.settingsOpened, 1);
  });

  testWidgets('not asked yet: asks, and refused does nothing more', (tester) async {
    final geo = GeolocatorPlatform.instance = _Geo(permission: LocationPermission.denied);
    await show(tester);
    await tester.tap(find.byKey(const Key('map-my-location')));
    await tester.pumpAndSettle();
    expect(geo.asked, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('allowed but not found: says so', (tester) async {
    GeolocatorPlatform.instance = _Geo();
    await show(tester);
    await tester.tap(find.byKey(const Key('map-my-location')));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Dein Standort ist gerade nicht bekannt'), findsOneWidget);
  });
}
