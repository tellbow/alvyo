import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/main.dart';
import 'package:alvyo/map_credit.dart';
import 'package:alvyo/place_layer.dart';
import 'package:alvyo/screens/about_screen.dart';

Widget app(Widget home) => MaterialApp(
  locale: const Locale('de'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('the credit names the offices of the overlays that are on', () {
    expect(MapCredit.text({'wanderwege'}), '© swisstopo · © OpenStreetMap');
    expect(
      MapCredit.text({'wanderland', 'jagdbanngebiete'}),
      '© swisstopo · © OpenStreetMap · © ASTRA, SchweizMobil · © BAFU',
    );
  });

  testWidgets('the map credit follows the overlays and lists every source on a tap', (tester) async {
    final settings = PlaceSettings();
    await tester.pumpWidget(app(Scaffold(body: MapCredit(settings: settings))));
    expect(find.text('© swisstopo · © OpenStreetMap'), findsOneWidget);

    settings.overlays.value = {'wildruhezonen'};
    await tester.pump();
    expect(find.text('© swisstopo · © OpenStreetMap · © BAFU'), findsOneWidget);

    await tester.tap(find.byKey(const Key('map-credit')));
    await tester.pumpAndSettle();
    final sources = find.byKey(const Key('data-sources'));
    expect(sources, findsOneWidget);
    expect(find.descendant(of: sources, matching: find.textContaining('(ODbL)', findRichText: true)), findsOneWidget);
    expect(
      find.descendant(of: sources, matching: find.textContaining('Quelle: MeteoSchweiz', findRichText: true)),
      findsOneWidget,
    );
  });

  testWidgets('about: sources, source code, licences, privacy', (tester) async {
    await tester.pumpWidget(app(const AboutScreen(server: 'https://alvyo.test')));
    expect(find.textContaining('swisstopo: Landeskarten', findRichText: true), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('about-operator')), 100);
    expect(find.text('Alvyo ist freie Software unter der AGPL-3.0.'), findsOneWidget);
    expect(find.byKey(const Key('about-source')), findsOneWidget);
    expect(find.byKey(const Key('about-privacy')), findsOneWidget);

    await tester.tap(find.byKey(const Key('about-licenses')));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  test('the fonts carry their licence (OFL)', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final entries = await fontLicenses().toList();
    expect(entries.map((e) => e.packages.single), ['Figtree', 'Bricolage Grotesque']);
    for (final e in entries) {
      expect(e.paragraphs.map((p) => p.text).join(' '), contains('SIL OPEN FONT LICENSE'));
    }
  });
}
