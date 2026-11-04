import 'dart:async';

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
import 'canton_map.dart';

/// What the user hiked, on one map and in numbers, by year; or, with
/// [username], what that user shares of it.
class HikedScreen extends StatefulWidget {
  const HikedScreen({super.key, required this.api, this.username, this.map});
  final Api api;
  final String? username;

  /// Replaces the map, in tests.
  final Widget? map;

  @override
  State<HikedScreen> createState() => _HikedScreenState();
}

class _HikedScreenState extends State<HikedScreen> {
  Hiked? _hiked;
  SharedHiked? _shared;
  Achievements? _achievements;
  List<String> _freshCantons = const [];
  Object? _error;
  int? _year;
  MapController? _map;
  StyleController? _style;

  bool get _loaded => _hiked != null || _shared != null;

  /// One entry per line drawn: the lines of a hike, or a shared line.
  List<List<List<List<double>>>> get _drawn => [
    for (final it in _hiked?.items ?? const <HikedItem>[]) it.lines,
    for (final l in _shared?.lines ?? const <List<List<double>>>[]) [l],
  ];

  List<List<double>> get _points => [
    for (final hike in _drawn)
      for (final l in hike) ...l,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      if (widget.username case final username?) {
        final shared = await widget.api.sharedHiked(username);
        if (mounted) setState(() => _shared = shared);
        return;
      }
      final hiked = await widget.api.hiked(year: _year);
      // All years together, so once is enough.
      if (_achievements == null) {
        final a = _achievements = await widget.api.achievements();
        unawaited(
          SeenCantons.instance.fresh(a.cantons).then((fresh) {
            if (mounted && fresh.isNotEmpty) setState(() => _freshCantons = fresh);
          }),
        );
      }
      if (!mounted) return;
      setState(() => _hiked = hiked);
      await _style?.updateGeoJsonSource(id: 'hiked', data: _geojson());
      final points = _points;
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

  String _geojson() => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final (i, hike) in _drawn.indexed)
        {
          'type': 'Feature',
          'properties': {'i': i},
          'geometry': {
            'type': 'MultiLineString',
            'coordinates': [
              for (final l in hike)
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
        // Someone else's lines lead nowhere.
        final map = _map, items = _hiked?.items;
        if (map == null || items == null) return;
        final found = map.featuresInRect(Rect.fromCircle(center: screenPoint, radius: 16), layerIds: ['hiked-line']);
        final i = (found.firstOrNull?.properties['i'] as num?)?.toInt();
        if (i != null && i < items.length) _open(items[i]);
      default:
    }
  }

  Widget _mapView() =>
      widget.map ??
      LayoutBuilder(
        builder: (context, size) {
          final view = fitLine(_points, size.maxWidth, size.maxHeight);
          return MapLibreMap(
            options: MapOptions(
              initStyle: swisstopoStyle(widget.api.server),
              initCenter: Geographic(lon: view.lon, lat: view.lat),
              initZoom: view.zoom,
            ),
            onEvent: _onEvent,
            onStyleLoaded: (style) async {
              _style = style;
              await style.addSource(GeoJsonSource(id: 'hiked', data: _geojson()));
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
    final shared = _shared;
    final title = shared != null ? t.hikedBy(shared.displayName) : (widget.username ?? t.hikedTitle);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: switch ((_loaded, _error)) {
        (false, null) => const Center(child: CircularProgressIndicator()),
        (false, final error?) => ErrorState(error: error, onRetry: _load),
        _ when _hiked?.years.isEmpty ?? false => Padding(
          padding: const EdgeInsets.all(16),
          child: Text(t.hikedEmpty, key: const Key('hiked-empty')),
        ),
        _ when _points.isEmpty && shared != null => _panel(t),
        _ => MapSplit(
          height: 340,
          map: Stack(
            children: [
              _mapView(),
              const Positioned(left: 8, bottom: 8, child: MapCredit()),
            ],
          ),
          panel: _panel(t),
        ),
      },
    );
  }

  Widget _panel(AppLocalizations t) {
    final hiked = _hiked, shared = _shared;
    final years = hiked?.years ?? shared?.years ?? const <HikedTotals>[];
    final total = hiked?.total ?? shared?.total;
    final totals = _year == null ? total : years.where((y) => y.year == _year).firstOrNull;
    final achievements = _achievements ?? shared?.achievements;
    Widget chip(String label, int? year) => ChoiceChip(
      key: Key('hiked-year-${year ?? 'all'}'),
      label: Text(label),
      selected: _year == year,
      onSelected: (_) {
        setState(() => _year = year);
        // The numbers of someone else are all here, and their map stays whole.
        if (shared == null) _load();
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
        Text(
          shared == null ? t.hikedPrivate : (shared.lines.isEmpty ? '' : t.hikedSharedMap),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (years.isNotEmpty)
          Wrap(spacing: 8, children: [chip(t.hikedAll, null), for (final y in years) chip('${y.year}', y.year)]),
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
        if (achievements != null) _AchievementsView(achievements: achievements, fresh: _freshCantons),
        for (final it in hiked?.items ?? const <HikedItem>[])
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

class _AchievementsView extends StatelessWidget {
  const _AchievementsView({required this.achievements, this.fresh = const []});
  final Achievements achievements;

  /// The cantons new since the last look.
  final List<String> fresh;

  static const _first = 5;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final a = achievements, text = Theme.of(context).textTheme;
    String names(List<String> list) =>
        list.length > _first ? '${list.take(_first).join(', ')} ${t.hikedMore(list.length - _first)}' : list.join(', ');
    Widget heading(String s) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(s, style: text.titleSmall),
    );
    final kinds = {
      'national': t.hikedOfficialNational,
      'regional': t.hikedOfficialRegional,
      'local': t.hikedOfficialLocal,
      'handicap': t.hikedOfficialHandicap,
    };
    return Column(
      key: const Key('achievements'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(t.hikedAchievements, style: text.titleMedium),
        heading('${t.hikedCantons}: ${t.hikedOf(a.cantons.length, a.cantonsTotal)}'),
        const SizedBox(height: 8),
        CantonMap(walked: a.cantons, fresh: fresh),
        if (fresh.isNotEmpty)
          Text(t.hikedNewCanton(fresh.join(', ')), key: const Key('hiked-new-canton'), style: text.titleSmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final c in a.cantons)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(c, style: text.labelMedium),
                ),
              ),
          ],
        ),
        if (a.official.isNotEmpty) heading(t.hikedOfficial),
        for (final o in a.official) Text('${kinds[o.kind] ?? o.kind}: ${t.hikedOf(o.done, o.total)}'),
        heading('${t.hikedSummits}: ${a.summits.length}'),
        if (a.summits.isNotEmpty)
          Text(names([for (final s in a.summits) s.ele == null ? s.name : '${s.name} (${formatHeight(s.ele!)})'])),
        heading('${t.hikedHuts}: ${a.huts.length}'),
        if (a.huts.isNotEmpty) Text(names(a.huts)),
        const SizedBox(height: 8),
      ],
    );
  }
}
