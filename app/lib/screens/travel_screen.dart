import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import '../api.dart';
import '../camera.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../map_style.dart';
import '../route_layers.dart';
import '../travel.dart';
import 'account_screens.dart';
import 'connections_screen.dart';

/// The way from a home to a journey's first stage ([to]) or back home from
/// its last: which home, leaving after or arriving before when, and the
/// connections; the chosen one is drawn on the map with the stage, rides
/// dashed and walks dotted. Pops with the travel as saved.
class TravelScreen extends StatefulWidget {
  const TravelScreen({
    super.key,
    required this.api,
    required this.journey,
    required this.travel,
    required this.to,
    this.map,
  });
  final Api api;
  final JourneyDetail journey;
  final JourneyTravel travel;
  final bool to;

  /// Stands in for the map in widget tests.
  @visibleForTesting
  final Widget? map;

  @override
  State<TravelScreen> createState() => _TravelScreenState();
}

class _TravelScreenState extends State<TravelScreen> {
  late JourneyTravel _travel = widget.travel;
  late Future<List<Home>> _homes = widget.api.homes();
  Future<List<Trip>>? _trips;
  int _chosen = 0;
  StyleController? _style;
  MapController? _map;
  Size? _mapSize;
  String? _error;

  TravelEnd? get _at {
    final t = AppLocalizations.of(context);
    final ends = journeyEnds(widget.journey, start: t.travelStart, end: t.travelEnd);
    return widget.to ? ends.start : ends.end;
  }

  TravelWay? get _way => widget.to ? _travel.to : _travel.back;

  @override
  void initState() {
    super.initState();
    _homes.then((_) => _search(), onError: (Object _) {});
  }

  Future<void> _search() async {
    final way = _way, at = _at;
    final homes = await _homes;
    final home = homes.where((h) => h.id == way?.homeId).firstOrNull;
    if (!mounted) return;
    if (way == null || home == null || at == null) {
      setState(() => _trips = null);
      _draw(null);
      return;
    }
    // Arriving by a time: the latest that fits first.
    final trips = travelTrips(
      widget.api,
      home,
      at,
      way,
      to: widget.to,
    ).then((t) => way.arrive ? t.reversed.toList() : t);
    setState(() {
      _trips = trips;
      _chosen = 0;
    });
    trips.then((t) => _draw(t.firstOrNull), onError: (Object _) {});
  }

  /// Saves a change of this direction; [way] null for none.
  Future<void> _set(TravelWay? way) async {
    final t = AppLocalizations.of(context);
    final next = widget.to ? JourneyTravel(to: way, back: _travel.back) : JourneyTravel(to: _travel.to, back: way);
    try {
      final saved = await widget.api.setTravel(widget.journey.id, next);
      if (!mounted) return;
      setState(() {
        _travel = saved;
        _error = null;
      });
      await _search();
    } on Object {
      if (mounted) setState(() => _error = t.errorServer);
    }
  }

  void _change({String? homeId, String? time, bool? arrive}) {
    final now = _way;
    final home = homeId ?? now?.homeId;
    if (home == null) return;
    _set(
      TravelWay(
        homeId: home,
        time: time ?? now?.time ?? (widget.to ? '07:00' : '17:00'),
        arrive: arrive ?? now?.arrive ?? false,
      ),
    );
  }

  static const _source = 'travel';

  /// The chosen trip's legs: rides dashed, walks dotted.
  void _draw(Trip? trip) {
    final data = jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        for (final l in trip?.legs ?? const <TripLeg>[])
          if (l.track.length > 1)
            {
              'type': 'Feature',
              'properties': {'kind': l.ride ? 'ride' : 'walk'},
              'geometry': {'type': 'LineString', 'coordinates': l.track},
            },
      ],
    });
    _style?.updateGeoJsonSource(id: _source, data: data).catchError((_) {});
    // The stage and the whole trip, home included.
    final at = _at, size = _mapSize, map = _map;
    if (at == null || size == null || map == null) return;
    final view = fitLine(
      [...at.line, for (final l in trip?.legs ?? const <TripLeg>[]) ...l.track],
      size.width,
      size.height,
      maxZoom: 13,
    );
    map
        .animateCamera(
          center: Geographic(lon: view.lon, lat: view.lat),
          zoom: view.zoom,
          nativeDuration: const Duration(milliseconds: 400),
        )
        .catchError((_) {});
  }

  Future<void> _addLayers(StyleController style) async {
    await style.addSource(const GeoJsonSource(id: _source, data: '{"type":"FeatureCollection","features":[]}'));
    await style.addLayer(
      const LineStyleLayer(
        id: 'travel-casing',
        sourceId: _source,
        paint: {'line-color': '#ffffff', 'line-width': 6, 'line-opacity': 0.8},
        layout: {'line-cap': 'round', 'line-join': 'round'},
      ),
    );
    await style.addLayer(
      const LineStyleLayer(
        id: 'travel-ride',
        sourceId: _source,
        filter: [
          '==',
          ['get', 'kind'],
          'ride',
        ],
        paint: {
          'line-color': '#1d4ed8',
          'line-width': 3.5,
          'line-dasharray': [2, 1.5],
        },
      ),
    );
    await style.addLayer(
      const LineStyleLayer(
        id: 'travel-walk',
        sourceId: _source,
        filter: [
          '==',
          ['get', 'kind'],
          'walk',
        ],
        paint: {
          'line-color': '#1d4ed8',
          'line-width': 3,
          'line-dasharray': [0.1, 2],
        },
        layout: {'line-cap': 'round'},
      ),
    );
    _style = style;
    final trips = await _trips?.catchError((_) => <Trip>[]);
    _draw(trips?.elementAtOrNull(_chosen));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final at = _at;
    final way = _way;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_travel);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.to ? t.travelTo : t.travelBack)),
        body: Column(
          children: [
            if (at != null)
              Expanded(
                flex: 4,
                child:
                    widget.map ??
                    LayoutBuilder(
                      builder: (context, size) {
                        final view = fitLine(at.line, size.maxWidth, size.maxHeight, maxZoom: 12);
                        _mapSize = size.biggest;
                        return MapLibreMap(
                          onEvent: (e) {
                            if (e is MapEventMapCreated) _map = e.mapController;
                          },
                          options: MapOptions(
                            initStyle: swisstopoStyle(widget.api.server),
                            initCenter: Geographic(lon: view.lon, lat: view.lat),
                            initZoom: view.zoom,
                          ),
                          onStyleLoaded: (style) async {
                            await addRouteLine(style, at.line);
                            await _addLayers(style);
                          },
                        );
                      },
                    ),
              ),
            Expanded(
              flex: 5,
              child: FutureBuilder(
                future: _homes,
                builder: (context, snap) {
                  if (snap.hasError) return Center(child: Text(t.errorServer));
                  final homes = snap.data;
                  if (homes == null) return const Center(child: CircularProgressIndicator());
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (at?.name case final name? when name.isNotEmpty)
                        Text(widget.to ? '→ $name' : '← $name', style: theme.textTheme.titleMedium),
                      if (homes.isEmpty) ...[
                        Text(t.travelNoHomes),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          key: const Key('travel-homes'),
                          onPressed: () async {
                            await Navigator.of(
                              context,
                            ).push(MaterialPageRoute<void>(builder: (_) => HomesScreen(api: widget.api)));
                            if (mounted) {
                              setState(() {
                                _homes = widget.api.homes();
                              });
                            }
                          },
                          child: Text(t.homesTitle),
                        ),
                      ] else ...[
                        const SizedBox(height: 8),
                        DropdownMenu<String>(
                          key: const Key('travel-home'),
                          label: Text(widget.to ? t.travelFrom : t.travelToHome),
                          expandedInsets: EdgeInsets.zero,
                          initialSelection: way?.homeId ?? '',
                          onSelected: (v) => v == null || v.isEmpty ? _set(null) : _change(homeId: v),
                          dropdownMenuEntries: [
                            DropdownMenuEntry(value: '', label: t.travelNone),
                            for (final h in homes) DropdownMenuEntry(value: h.id, label: h.name),
                          ],
                        ),
                        if (way != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            spacing: 8,
                            children: [
                              SegmentedButton<bool>(
                                key: const Key('travel-mode'),
                                showSelectedIcon: false,
                                segments: [
                                  ButtonSegment(value: false, label: Text(t.connectionsDepart)),
                                  ButtonSegment(value: true, label: Text(t.connectionsArrive)),
                                ],
                                selected: {way.arrive},
                                onSelectionChanged: (s) => _change(arrive: s.first),
                              ),
                              OutlinedButton(
                                key: const Key('travel-time'),
                                onPressed: () async {
                                  final parts = way.time.split(':');
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
                                  );
                                  if (picked == null) return;
                                  String two(int n) => n.toString().padLeft(2, '0');
                                  _change(time: '${two(picked.hour)}:${two(picked.minute)}');
                                },
                                child: Text(way.time),
                              ),
                            ],
                          ),
                        ],
                      ],
                      if (_error case final e?)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(e, style: TextStyle(color: theme.colorScheme.error)),
                        ),
                      if (way != null && at == null) ...[
                        const SizedBox(height: 12),
                        Text(t.travelNoRoute, style: muted),
                      ] else if (way != null && at != null) ...[
                        const SizedBox(height: 12),
                        Text(at.day != null ? t.travelOn(formatDate(at.day!)) : t.travelNoDate, style: muted),
                        const SizedBox(height: 8),
                        FutureBuilder(
                          future: _trips,
                          builder: (context, snap) {
                            if (snap.connectionState != ConnectionState.done) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            if (snap.hasError) {
                              final e = snap.error;
                              return Text(
                                e is ApiException && e.status == 429 ? t.shareRate : t.connectionsUnavailable,
                              );
                            }
                            final trips = snap.data ?? const <Trip>[];
                            if (trips.isEmpty) return Text(key: const Key('travel-none'), t.connectionsNone);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final (i, trip) in trips.indexed)
                                  TripCard(
                                    key: Key('travel-trip-$i'),
                                    trip: trip,
                                    selected: i == _chosen,
                                    onTap: () {
                                      setState(() => _chosen = i);
                                      _draw(trip);
                                    },
                                  ),
                                Text(t.connectionsSource, style: theme.textTheme.bodySmall?.merge(muted)),
                              ],
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(t.travelPrivate, style: theme.textTheme.bodySmall?.merge(muted)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// When planning a journey: from which home to the start and back to which,
/// leaving after or arriving before when. Nothing without homes.
class TravelChoice extends StatefulWidget {
  const TravelChoice({super.key, required this.api, required this.onChanged});
  final Api api;
  final ValueChanged<JourneyTravel> onChanged;

  @override
  State<TravelChoice> createState() => _TravelChoiceState();
}

class _TravelChoiceState extends State<TravelChoice> {
  late final Future<List<Home>> _homes = widget.api.homes().catchError((_) => <Home>[]);
  var _travel = const JourneyTravel();

  void _set(bool to, {String? homeId, String? time, bool? arrive}) {
    final now = to ? _travel.to : _travel.back;
    final home = homeId ?? now?.homeId ?? '';
    final way = home.isEmpty
        ? null
        : TravelWay(
            homeId: home,
            time: time ?? now?.time ?? (to ? '07:00' : '17:00'),
            arrive: arrive ?? now?.arrive ?? false,
          );
    setState(
      () => _travel = to ? JourneyTravel(to: way, back: _travel.back) : JourneyTravel(to: _travel.to, back: way),
    );
    widget.onChanged(_travel);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FutureBuilder(
      future: _homes,
      builder: (context, snap) {
        final homes = snap.data ?? const <Home>[];
        if (homes.isEmpty) return const SizedBox.shrink();
        Widget direction(bool to) {
          final way = to ? _travel.to : _travel.back;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              DropdownMenu<String>(
                key: Key(to ? 'jplan-travel-to' : 'jplan-travel-back'),
                label: Text('${to ? t.travelTo : t.travelBack} · ${to ? t.travelFrom : t.travelToHome}'),
                expandedInsets: EdgeInsets.zero,
                initialSelection: way?.homeId ?? '',
                onSelected: (v) => _set(to, homeId: v ?? ''),
                dropdownMenuEntries: [
                  DropdownMenuEntry(value: '', label: t.travelNone),
                  for (final h in homes) DropdownMenuEntry(value: h.id, label: h.name),
                ],
              ),
              if (way != null)
                Row(
                  spacing: 8,
                  children: [
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: false, label: Text(t.connectionsDepart)),
                        ButtonSegment(value: true, label: Text(t.connectionsArrive)),
                      ],
                      selected: {way.arrive},
                      onSelectionChanged: (s) => _set(to, arrive: s.first),
                    ),
                    OutlinedButton(
                      key: Key(to ? 'jplan-travel-to-time' : 'jplan-travel-back-time'),
                      onPressed: () async {
                        final parts = way.time.split(':');
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
                        );
                        if (picked == null) return;
                        String two(int n) => n.toString().padLeft(2, '0');
                        _set(to, time: '${two(picked.hour)}:${two(picked.minute)}');
                      },
                      child: Text(way.time),
                    ),
                  ],
                ),
            ],
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Text(t.travelTitle, style: Theme.of(context).textTheme.titleSmall),
              direction(true),
              direction(false),
            ],
          ),
        );
      },
    );
  }
}
