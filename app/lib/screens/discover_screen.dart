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
import '../navigation/gps.dart';
import '../place_layer.dart';
import '../precip.dart';
import 'details.dart';
import 'journey_screen.dart';
import 'route_screen.dart';
import 'wide.dart';

/// The line colours, cycled through the results as on the website.
const discoverColors = [
  Color(0xffa21caf),
  Color(0xff4d7c0f),
  Color(0xff2563eb),
  Color(0xffc2410c),
  Color(0xff0f766e),
  Color(0xffbe123c),
];

Color discoverColor(int i) => discoverColors[i % discoverColors.length];

/// The map part of the screen: draws [items], reports the [onView] when the
/// camera rests and [onOpen]s a tapped line. Swapped out in widget tests,
/// where a map cannot render.
typedef DiscoverMapBuilder =
    Widget Function(List<DiscoverItem> items, ValueChanged<Bbox> onView, ValueChanged<DiscoverItem> onOpen);

/// Hiking time filters in hours as the hiker walks them; 0: open.
enum DiscoverHours {
  any(0, 0),
  short(0, 2),
  medium(2, 4),
  long(4, 6),
  xlong(6, 0);

  const DiscoverHours(this.from, this.to);
  final int from, to;
}

enum _Status { loading, done, failed, offline }

/// Public routes and journeys in the map's view, as the website's «Entdecken»:
/// lines on the map and a list, with filters. [mine]: the user's own routes,
/// journeys and hikes instead, as the website's map of one's tours.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    required this.api,
    this.mine = false,
    this.embedded = false,
    this.start,
    @visibleForTesting this.map,
  });
  final Api api;
  final bool mine;

  /// Where the map starts (a place searched on Entdecken); else where the
  /// phone is.
  final LonLat? start;

  /// Without its app bar, inside a tab (Touren › Karte).
  final bool embedded;
  final DiscoverMapBuilder? map;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  /// The hiker's pace: times are shown and filtered as they walk.
  late final Future<double> _speedFactor = widget.api
      .me()
      .timeout(const Duration(seconds: 5))
      .then((m) => m.speedFactor)
      .catchError((_) => 1.0);
  double _pace = 1;

  String _kind = ''; // route, journey, or both
  String _origin = ''; // the official routes (only), people's (none), or both
  int _sac = 0;
  String _done = ''; // one's map: planned, done (hiked), or both
  var _hours = DiscoverHours.any;

  Bbox? _view;
  Timer? _timer;
  int _asked = 0; // only the latest answer is shown
  var _status = _Status.loading;
  List<DiscoverItem> _items = const [];
  bool _more = false;

  @override
  void dispose() {
    _timer?.cancel();
    _asked++;
    super.dispose();
  }

  void _viewed(Bbox view) {
    _view = view;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), _search);
  }

  Future<void> _search() async {
    final view = _view;
    if (view == null) return;
    final asked = ++_asked;
    setState(() => _status = _Status.loading);
    final pace = await _speedFactor;
    // The server compares Swiss hiking time.
    int? seconds(int h) => h == 0 ? null : (h * 3600 / pace).round();
    _Status status;
    ({List<DiscoverItem> items, bool more})? found;
    try {
      found = widget.mine
          ? await widget.api.myMap(
              view,
              kind: _kind.isEmpty ? null : _kind,
              sacMax: _sac,
              durationMin: seconds(_hours.from),
              durationMax: seconds(_hours.to),
              done: _done.isEmpty ? null : _done,
            )
          : await widget.api.discover(
              view,
              kind: _kind.isEmpty ? null : _kind,
              official: _origin.isEmpty ? null : _origin,
              sacMax: _sac,
              durationMin: seconds(_hours.from),
              durationMax: seconds(_hours.to),
            );
      status = _Status.done;
    } on ApiException {
      status = _Status.failed;
    } on Object {
      status = _Status.offline;
    }
    if (!mounted || asked != _asked) return;
    setState(() {
      _pace = pace;
      _status = status;
      _items = found?.items ?? const [];
      _more = found?.more ?? false;
    });
  }

  void _filter(VoidCallback change) {
    setState(change);
    _timer?.cancel();
    _search();
  }

  Future<void> _open(DiscoverItem it) => Navigator.of(context).push(
    MaterialPageRoute(
      // A recorded hike (in the user's map) is a route.
      builder: (_) => it.kind == 'journey'
          ? JourneyScreen(api: widget.api, id: it.id, title: it.title)
          : RouteScreen(api: widget.api, id: it.id, title: it.title),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final map =
        widget.map ??
        (items, onView, onOpen) =>
            _DiscoverMap(api: widget.api, items: items, onView: onView, onOpen: onOpen, start: widget.start);
    final body = MapSplit(
      share: 4 / 9,
      map: map(_items, _viewed, _open),
      panel: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_status == _Status.loading) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
          _filters(t),
          Expanded(child: _results(t)),
        ],
      ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(widget.mine ? t.myMapTitle : t.discoverTitle)),
      body: body,
    );
  }

  Widget _filters(AppLocalizations t) {
    Widget menu<T>(String key, T value, List<T> values, String Function(T) label, void Function(T) set, bool active) =>
        PopupMenuButton<T>(
          key: Key('discover-$key'),
          initialValue: value,
          onSelected: (v) => _filter(() => set(v)),
          itemBuilder: (_) => [
            for (final v in values)
              PopupMenuItem(key: Key('discover-$key-${v is Enum ? v.name : v}'), value: v, child: Text(label(v))),
          ],
          child: Chip(
            backgroundColor: active ? Theme.of(context).colorScheme.secondaryContainer : null,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [Text(label(value)), const Icon(Icons.arrow_drop_down, size: 18)],
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            spacing: 8,
            children: [
              menu(
                'kind',
                _kind,
                ['', 'route', 'journey', if (widget.mine) 'hike'],
                (k) => switch (k) {
                  'route' => t.discoverKindRoute,
                  'journey' => t.discoverKindJourney,
                  'hike' => t.myMapKindHike,
                  _ => t.discoverKindAll,
                },
                (k) => _kind = k,
                _kind.isNotEmpty,
              ),
              if (!widget.mine)
                menu(
                  'origin',
                  _origin,
                  ['', 'only', 'none'],
                  (o) => switch (o) {
                    'only' => t.discoverOriginOnly,
                    'none' => t.discoverOriginNone,
                    _ => t.discoverOriginAll,
                  },
                  (o) => _origin = o,
                  _origin.isNotEmpty,
                ),
              menu(
                'hours',
                _hours,
                DiscoverHours.values,
                (h) => switch (h) {
                  DiscoverHours.any => t.discoverDurationAny,
                  DiscoverHours.short => t.discoverDurationShort,
                  DiscoverHours.medium => t.discoverDurationMedium,
                  DiscoverHours.long => t.discoverDurationLong,
                  DiscoverHours.xlong => t.discoverDurationXlong,
                },
                (h) => _hours = h,
                _hours != DiscoverHours.any,
              ),
              menu(
                'sac',
                _sac,
                [0, 1, 2, 3, 4, 5, 6],
                (g) => g == 0 ? t.discoverSacAny : t.discoverSacMax('T$g'),
                (g) => _sac = g,
                _sac > 0,
              ),
              if (widget.mine)
                menu(
                  'done',
                  _done,
                  ['', 'planned', 'done'],
                  (d) => switch (d) {
                    'planned' => t.doneFilterPlanned,
                    'done' => t.doneFilterDone,
                    _ => t.doneFilterAll,
                  },
                  (d) => _done = d,
                  _done.isNotEmpty,
                ),
            ],
          ),
        ),
        if (_hours != DiscoverHours.any && _kind != 'route')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(t.discoverDurationHint, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }

  Widget _results(AppLocalizations t) {
    Widget message(Key key, IconData? icon, String text, {bool retry = false}) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          key: key,
          spacing: 12,
          children: [
            if (icon != null) Icon(icon),
            Expanded(child: Text(text)),
          ],
        ),
        if (retry)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(key: const Key('discover-retry'), onPressed: _search, child: Text(t.discoverRetry)),
          ),
      ],
    );
    switch (_status) {
      case _Status.offline:
        return message(const Key('discover-offline'), Icons.cloud_off, t.discoverOffline, retry: true);
      case _Status.failed:
        return message(const Key('discover-failed'), Icons.error_outline, t.discoverFailed, retry: true);
      case _Status.done when _items.isEmpty:
        return message(const Key('discover-empty'), null, widget.mine ? t.myMapEmpty : t.discoverEmpty);
      default:
    }
    final small = Theme.of(context).textTheme.bodySmall;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _items.length + (_more ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _items.length) {
          return Padding(
            key: const Key('discover-more'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(t.discoverMore, style: small),
          );
        }
        final it = _items[i];
        final journey = it.kind == 'journey';
        return ListTile(
          key: Key('discover-item-$i'),
          leading: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: discoverColor(i), shape: BoxShape.circle),
          ),
          minLeadingWidth: 12,
          title: Text(it.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            [
              [
                journey ? t.discoverJourney : t.discoverRoute,
                if (it.official case final o?) officialLabel(t, o) else if (!widget.mine) t.discoverBy(it.owner),
              ].join(' · '),
              '${formatDistance(it.distanceM)} · ${formatDuration(it.durationS, _pace)} · ↑\u00a0${formatHeight(it.ascentM)}'
                  '${it.sacGrade > 0 ? ' · ${formatSac(it.sacGrade, it.sacMax)}' : ''}',
              if (journey) '${t.discoverStages(it.stages)} · ${t.discoverLongest(formatDuration(it.longestS, _pace))}',
            ].join('\n'),
          ),
          isThreeLine: true,
          onTap: () => _open(it),
        );
      },
    );
  }
}

/// The national map with huts, starting where the phone is (if the app may
/// know) or on all of Switzerland, and the results as coloured lines.
class _DiscoverMap extends StatefulWidget {
  const _DiscoverMap({required this.api, required this.items, required this.onView, required this.onOpen, this.start});
  final Api api;
  final LonLat? start;
  final List<DiscoverItem> items;
  final ValueChanged<Bbox> onView;
  final ValueChanged<DiscoverItem> onOpen;

  @override
  State<_DiscoverMap> createState() => _DiscoverMapState();
}

class _DiscoverMapState extends State<_DiscoverMap> {
  late final Future<LonLat?> _here = widget.start != null ? Future.value(widget.start) : knownPosition();
  late final _places = PlaceLayer(widget.api, onTap: (p) => showPlace(context, p));
  MapController? _map;
  StyleController? _style;

  static const _source = 'discover';
  static const _line = 'discover-line';

  @override
  void dispose() {
    _places.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_DiscoverMap old) {
    super.didUpdateWidget(old);
    if (old.items != widget.items) _draw();
  }

  void _draw() => _style?.updateGeoJsonSource(id: _source, data: _geojson(widget.items)).catchError((_) {});

  void _onEvent(MapEvent e) {
    _places.onEvent(e);
    switch (e) {
      case MapEventMapCreated(:final mapController):
        _map = mapController;
      case MapEventCameraIdle():
        _report();
      case MapEventClick(:final screenPoint):
        _tap(screenPoint);
      default:
    }
  }

  void _report() {
    final b = _map?.getVisibleRegion();
    if (b == null) return;
    widget.onView((west: b.longitudeWest, south: b.latitudeSouth, east: b.longitudeEast, north: b.latitudeNorth));
  }

  /// A finger is wider than a line; a hut on a line opens the hut.
  void _tap(Offset at) {
    final map = _map;
    if (map == null || _style == null) return;
    final area = Rect.fromCircle(center: at, radius: 16);
    if (map.featuresInRect(area, layerIds: ['places']).isNotEmpty) return;
    final found = map.featuresInRect(area, layerIds: [_line]);
    if (found.isEmpty) return;
    final id = found.first.properties['id'];
    if (widget.items.where((it) => it.id == id).firstOrNull case final it?) widget.onOpen(it);
  }

  static String _hex(Color c) => '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';

  static String _geojson(List<DiscoverItem> items) => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final (i, it) in items.indexed)
        {
          'type': 'Feature',
          'properties': {'id': it.id, 'color': _hex(discoverColor(i))},
          'geometry': {'type': 'MultiLineString', 'coordinates': it.lines},
        },
    ],
  });

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _here,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const SizedBox.expand();
      final here = snap.data;
      final inside =
          here != null &&
          here.lon > chBounds[0] &&
          here.lat > chBounds[1] &&
          here.lon < chBounds[2] &&
          here.lat < chBounds[3];
      return Stack(
        children: [
          LayoutBuilder(
            builder: (context, size) {
              final view = inside
                  ? (lon: here.lon, lat: here.lat, zoom: 11.0)
                  : fitLine(
                      const [
                        [5.96, 45.82],
                        [10.49, 47.81],
                      ],
                      size.maxWidth,
                      size.maxHeight,
                      padding: 8,
                    );
              return MapLibreMap(
                options: MapOptions(
                  initStyle: swisstopoStyle(widget.api.server),
                  initCenter: Geographic(lon: view.lon, lat: view.lat),
                  initZoom: view.zoom,
                ),
                onEvent: _onEvent,
                onStyleLoaded: (style) async {
                  await _places.addTo(style);
                  await style.addSource(GeoJsonSource(id: _source, data: _geojson(widget.items)));
                  await style.addLayer(
                    const LineStyleLayer(
                      id: 'discover-casing',
                      sourceId: _source,
                      paint: {'line-color': '#ffffff', 'line-width': 7, 'line-opacity': 0.85},
                      layout: {'line-cap': 'round', 'line-join': 'round'},
                    ),
                  );
                  await style.addLayer(
                    const LineStyleLayer(
                      id: _line,
                      sourceId: _source,
                      paint: {
                        'line-color': ['get', 'color'],
                        'line-width': 4,
                      },
                      layout: {'line-cap': 'round', 'line-join': 'round'},
                    ),
                  );
                  _style = style;
                  _draw(); // results that came meanwhile
                  _report(); // in case the camera rested before
                },
              );
            },
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 64,
            child: MapCorner(precip: PrecipBar(controller: _places.precip)),
          ),
          const Positioned(top: 12, right: 12, child: PlaceLayerButton()),
        ],
      );
    },
  );
}
