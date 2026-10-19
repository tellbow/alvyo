import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'l10n/app_localizations.dart';
import 'place_layer.dart';
import 'precip.dart';
import 'snow.dart';

/// Who to credit for what the map shows, always in sight: swisstopo asks
/// for its source on every map, OpenStreetMap for one that needs no tap
/// (its paths, huts and the routes computed on them), and the federal
/// offices of the overlays that are on. A tap lists every source.
class MapCredit extends StatelessWidget {
  const MapCredit({super.key, this.settings});

  /// The overlays shown; [PlaceSettings.instance] by default.
  final PlaceSettings? settings;

  /// The credit line for [overlays].
  static String text(Set<String> overlays) => [
    '© swisstopo',
    '© OpenStreetMap',
    if (overlays.contains('wanderland')) '© ASTRA, SchweizMobil',
    if (overlays.contains('wildruhezonen') || overlays.contains('jagdbanngebiete')) '© BAFU',
    if (overlays.contains('snow')) 'Copernicus (EU)',
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final overlays = (settings ?? PlaceSettings.instance).overlays;
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: t.mapCreditLabel,
        child: Material(
          color: theme.colorScheme.surface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: const Key('map-credit'),
            borderRadius: BorderRadius.circular(8),
            // Not over the whole screen: the map stays in sight above, a
            // tap there or pulling the sheet down leads back.
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (context) => DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.6,
                maxChildSize: 0.9,
                builder: (context, scroll) => SafeArea(
                  child: SingleChildScrollView(
                    controller: scroll,
                    padding: const EdgeInsets.all(16),
                    child: const DataSources(),
                  ),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: ValueListenableBuilder(
                valueListenable: overlays,
                builder: (context, on, _) => Text(text(on), style: theme.textTheme.labelSmall),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bars of the rain and the snow cover and the credit in the map's
/// upper left corner: there no sheet covers the credit.
class MapCorner extends StatelessWidget {
  const MapCorner({super.key, required this.places});

  final PlaceLayer places;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      PrecipBar(controller: places.precip),
      const SizedBox(height: 4),
      SnowBar(controller: places.snow),
      const SizedBox(height: 4),
      const MapCredit(),
    ],
  );
}

/// One data source: what it gives, and a link to its terms.
typedef DataSource = ({String text, String? terms, String? href});

const _ogd = ('opendata.swiss', 'https://opendata.swiss/en/terms-of-use');

/// Every outside data source the app shows, as on the website's about page
/// (web/src/lib/about/sources.ts) and in NOTICE.
List<DataSource> dataSources(AppLocalizations t) => [
  (
    text: t.aboutSrcSwisstopo,
    terms: 'OGD, © swisstopo',
    href: 'https://www.swisstopo.admin.ch/en/terms-of-use-free-geodata-and-geoservices',
  ),
  (text: t.aboutSrcAstra, terms: _ogd.$1, href: _ogd.$2),
  (text: t.aboutSrcBafu, terms: _ogd.$1, href: _ogd.$2),
  (text: t.aboutSrcVbs, terms: _ogd.$1, href: _ogd.$2),
  (text: t.aboutSrcMeteo, terms: 'CC BY 4.0', href: 'https://opendatadocs.meteoswiss.ch/general/terms-of-use'),
  (text: t.aboutSrcCopernicus, terms: 'CLMS data policy', href: 'https://land.copernicus.eu/en/data-policy'),
  (
    text: t.aboutSrcTransport,
    terms: 'opentransportdata.swiss',
    href: 'https://opentransportdata.swiss/en/terms-of-use/',
  ),
  (text: t.aboutSrcBav, terms: _ogd.$1, href: _ogd.$2),
  (text: t.aboutSrcOsm, terms: 'ODbL', href: 'https://www.openstreetmap.org/copyright'),
  (text: t.aboutSrcMapterhorn, terms: 'mapterhorn.com/attribution', href: 'https://mapterhorn.com/attribution'),
  (text: t.aboutSrcTerrain, terms: 'Mapzen', href: 'https://github.com/tilezen/joerd/blob/master/docs/attribution.md'),
  (text: t.aboutSrcHikingtime, terms: null, href: null),
];

/// The data sources with their terms, each a tap away.
class DataSources extends StatelessWidget {
  const DataSources({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      key: const Key('data-sources'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.aboutDataIntro),
        const SizedBox(height: 8),
        for (final s in dataSources(t))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: InkWell(
              onTap: s.href == null ? null : () => launchUrl(Uri.parse(s.href!), mode: LaunchMode.externalApplication),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: s.terms == null ? s.text : '${s.text} '),
                    if (s.terms != null)
                      TextSpan(
                        text: '(${s.terms})',
                        style: TextStyle(color: theme.colorScheme.primary, decoration: TextDecoration.underline),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
