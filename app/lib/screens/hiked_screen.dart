import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import '../api.dart';
import '../camera.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../map_credit.dart';
import '../map_style.dart';
import '../route_layers.dart';
import 'error_state.dart';
import 'journey_screen.dart';
import 'route_screen.dart';
import 'wide.dart';

/// What the user hiked, on one map and in numbers, by year. Only they see it.
class HikedScreen extends StatefulWidget {
  const HikedScreen({super.key, required this.api, this.map});
  final Api api;

  /// Replaces the map, in tests.
  final Widget? map;

  @override
  State<HikedScreen> createState() => _HikedScreenState();
}

class _HikedScreenState extends State<HikedScreen> {
  Hiked? _hiked;
  Object? _error;
  int? _year;
  MapController? _map;
  StyleController? _style;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final hiked = await widget.api.hiked(year: _year);
      if (!mounted) return;
      setState(() => _hiked = hiked);
      await _style?.updateGeoJsonSource(id: 'hiked', data: _geojson(hiked.items));
      final points = [
        for (final it in hiked.items)
          for (final l in it.lines) ...l,
      ];
      if (points.length >= 2) {
        await _map?.fitBounds(
          bounds: LngLatBounds.fromPoints([for (final p in points) Geographic(lon: p[0], lat: p[1])]),
          padding: const EdgeInsets.all(48),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _geojson(List<HikedItem> items) => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final (i, it) in items.indexed)
        {
          'type': 'Feature',
          'properties': {'i': i},
          'geometry': {
            'type': 'MultiLineString',
            'coordinates': [
              for (final l in it.lines)
                [
                  for (final c in l) [c[0], c[1]],
                ],
            ],
          },
        },
    ],
  });

  void _open(HikedItem it) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => it.kind == 'journey'
          ? JourneyScreen(api: widget.api, id: it.id, title: it.title)
          : RouteScreen(api: widget.api, id: it.id, title: it.title),
    ),
  );

  void _onEvent(MapEvent e) {
    switch (e) {
      case MapEventMapCreated(:final mapController):
        _map = mapController;
      case MapEventClick(:final screenPoint):
        final map = _map, items = _hiked?.items;
        if (map == null || items == null) return;
        final found = map.featuresInRect(Rect.fromCircle(center: screenPoint, radius: 16), layerIds: ['hiked-line']);
        final i = (found.firstOrNull?.properties['i'] as num?)?.toInt();
        if (i != null && i < items.length) _open(items[i]);
      default:
    }
  }

  Widget _mapView(Hiked hiked) =>
      widget.map ??
      LayoutBuilder(
        builder: (context, size) {
          final view = fitLine(
            [
              for (final it in hiked.items)
                for (final l in it.lines) ...l,
            ],
            size.maxWidth,
            size.maxHeight,
          );
          return MapLibreMap(
            options: MapOptions(
              initStyle: swisstopoStyle(widget.api.server),
              initCenter: Geographic(lon: view.lon, lat: view.lat),
              initZoom: view.zoom,
            ),
            onEvent: _onEvent,
            onStyleLoaded: (style) async {
              _style = style;
              await style.addSource(GeoJsonSource(id: 'hiked', data: _geojson(_hiked?.items ?? const [])));
              // See-through without a casing: paths walked more often get darker.
              await style.addLayer(
                LineStyleLayer(
                  id: 'hiked-line',
                  sourceId: 'hiked',
                  paint: {'line-color': stageColors.first, 'line-width': 4, 'line-opacity': 0.6},
                  layout: const {'line-cap': 'round', 'line-join': 'round'},
                ),
              );
            },
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final hiked = _hiked;
    return Scaffold(
      appBar: AppBar(title: Text(t.hikedTitle)),
      body: switch ((hiked, _error)) {
        (null, null) => const Center(child: CircularProgressIndicator()),
        (null, final error?) => ErrorState(error: error, onRetry: _load),
        (final hiked?, _) when hiked.years.isEmpty => Padding(
          padding: const EdgeInsets.all(16),
          child: Text(t.hikedEmpty, key: const Key('hiked-empty')),
        ),
        (final hiked?, _) => MapSplit(
          height: 340,
          map: Stack(
            children: [
              _mapView(hiked),
              const Positioned(left: 8, bottom: 8, child: MapCredit()),
            ],
          ),
          panel: _panel(t, hiked),
        ),
      },
    );
  }

  Widget _panel(AppLocalizations t, Hiked hiked) {
    final totals = _year == null ? hiked.total : hiked.years.where((y) => y.year == _year).firstOrNull;
    Widget chip(String label, int? year) => ChoiceChip(
      key: Key('hiked-year-${year ?? 'all'}'),
      label: Text(label),
      selected: _year == year,
      onSelected: (_) {
        setState(() => _year = year);
        _load();
      },
    );
    Widget stat(String label, String value) => SizedBox(
      width: 150,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: Text(value, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
    return ListView(
      key: const Key('hiked-list'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(t.hikedPrivate, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [chip(t.hikedAll, null), for (final y in hiked.years) chip('${y.year}', y.year)]),
        if (totals != null)
          Wrap(
            key: const Key('hiked-stats'),
            spacing: 8,
            children: [
              stat(t.hikedHikes, '${totals.hikes}'),
              stat(t.hikedDistance, formatDistance(totals.distanceM)),
              stat(t.hikedAscent, formatHeight(totals.ascentM)),
              stat(t.hikedTime, formatDuration(totals.timeS)),
              stat(t.hikedHighest, totals.highestM > 0 ? formatHeight(totals.highestM) : '–'),
              stat(t.hikedLongest, formatDistance(totals.longestM)),
            ],
          ),
        for (final it in hiked.items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(it.title),
            subtitle: Text(
              '${formatDate(DateTime.parse(it.on))} · ${formatDistance(it.distanceM)} · ↑ ${formatHeight(it.ascentM)}',
            ),
            onTap: () => _open(it),
          ),
      ],
    );
  }
}
