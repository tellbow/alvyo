import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart' show GlobalWidgetsLocalizations;
import 'package:cupertino_ui/cupertino_ui.dart' show GlobalCupertinoLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart';
// What MapLibreMap puts around its children; not exported.
// ignore: depend_on_referenced_packages, implementation_imports
import 'package:maplibre_platform_interface/src/widget/inherited_model.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/north_button.dart';

class _Map extends Fake implements MapController {
  final turnedTo = <double?>[];

  @override
  Future<void> animateCamera({
    Geographic? center,
    double? zoom,
    double? bearing,
    double? pitch,
    Duration nativeDuration = const Duration(seconds: 2),
    double webSpeed = 1.2,
    Duration? webMaxDuration,
    EdgeInsets padding = EdgeInsets.zero,
  }) async => turnedTo.add(bearing);
}

void main() {
  Future<_Map> show(WidgetTester tester, double bearing) async {
    final map = _Map();
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
          body: MapLibreInheritedModel(
            mapController: map,
            mapCamera: MapCamera(center: Geographic(lon: 8.23, lat: 46.8), zoom: 8, bearing: bearing, pitch: 0),
            child: const NorthButton(),
          ),
        ),
      ),
    );
    return map;
  }

  testWidgets('north up: no button', (tester) async {
    await show(tester, 0);
    expect(find.byKey(const Key('map-north')), findsNothing);
    await show(tester, 359.8);
    expect(find.byKey(const Key('map-north')), findsNothing);
  });

  testWidgets('rotated: the button turns the map back to north', (tester) async {
    final map = await show(tester, 37);
    expect(find.byTooltip('Nach Norden ausrichten'), findsOneWidget);
    await tester.tap(find.byKey(const Key('map-north')));
    expect(map.turnedTo, [0]);
  });
}
