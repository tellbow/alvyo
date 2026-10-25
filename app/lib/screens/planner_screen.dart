import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import '../api.dart';
import '../bug_report.dart';
import '../drag_ways.dart';
import '../camera.dart';
import '../elevation_profile.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../map_credit.dart';
import '../map_style.dart';
import '../place_layer.dart';
import '../place_search.dart';
import '../planner.dart';
import '../route_layers.dart';
import 'plan_sheet.dart';
import 'route_screen.dart';

/// Plans a route from A to B, as on the website: points by tapping the map
/// or by search, the legs between them computed, then saved and opened.
class PlannerScreen extends StatefulWidget {
  const PlannerScreen({
    super.key,
    required this.api,
    this.map,
    this.stage,
    this.start,
    this.plan,
    this.edit,
    this.embedded = false,
    this.onSaved,
  });
  final Api api;

  /// Inside Planen (requirement 69): without its app bar; a saved route is
  /// opened on top and [onSaved] called (the tab then starts a new plan).
  final bool embedded;
  final VoidCallback? onSaved;

  /// Plans the route of this stage (without one yet); pops with the journey.
  final ({String journeyId, String stageId, String title})? stage;

  /// The first point, e.g. where the previous stage ends.
  final LonLat? start;

  /// A route from a start ([name] if it is a place) to a destination, e.g.
  /// from «Wie weit komme ich?»: its profile, and back to the start or not.
  final ({LonLat from, String? name, LonLat to, String profile, bool roundTrip})? plan;

  /// Changes this route's line: start, destination and every point
  /// between; pops with the route saved.
  final RouteDetail? edit;

  /// Instead of the map, in widget tests (MapLibre cannot render there).
  @visibleForTesting
  final Widget? map;

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> with ReportsPlace<PlannerScreen> {
  @override
  String get place => switch ((widget.edit, widget.stage)) {
    (final r?, _) => '/plan/${r.id}',
    (_, final st?) => '/journeys/${st.journeyId}/stages/${st.stageId}/plan',
    _ => '/plan',
  };

  late final _planner = RoutePlanner(widget.api)..addListener(_changed);
  late final _places = PlaceLayer(widget.api, onTap: _showPlace);
  MapController? _map;
  StyleController? _style;
  double _pace = 1;
  bool _saving = false;

  /// The search for a stop before the destination is open.
  bool _via = false;

  /// Where the points are on the map, for dragging them (feedback issue
  /// 12): MapLibre reports taps on its features but no drags.
  final _handles = ValueNotifier<List<Offset>>(const []);

  /// The point being dragged and where the finger is.
  ({int index, Offset at})? _drag;

  /// A dot halfway along each leg between two points (not the way back of a
  /// round trip): dragged, the leg takes another way or gets a stop.
  final _legHandles = ValueNotifier<List<Offset>>(const []);

  /// The leg being dragged, where the finger is, and the other ways between
  /// its points once they have come.
  ({int leg, Offset at, List<({Way way, int index})>? ways})? _legDrag;
  Future<void>? _waysComing;

  /// Where the other ways' points are on the screen (the map holds still
  /// while a leg is dragged), and the one within reach of the finger.
  final _waysOnScreen = Map<List<double>, Offset>.identity();
  int? _inReach;

  // Built once: the screen rebuilds with every leg.
  late final Widget _mapView = widget.map ?? _buildMap();

  @override
  void initState() {
    super.initState();
    if (widget.edit case final r?) {
      _planner.load(r.profile, r.anchors, r.legs);
    } else if (widget.start case final p?) {
      _planner.add(p.lon, p.lat);
    } else if (widget.plan case final p?) {
      _planner
        ..setProfile(p.profile)
        ..setRoundTrip(p.roundTrip)
        ..add(p.from.lon, p.from.lat, name: p.name)
        ..add(p.to.lon, p.to.lat);
    }
    widget.api
        .me()
        .then((me) {
          if (mounted) setState(() => _pace = me.speedFactor);
        })
        .catchError((_) {}); // signpost pace
  }

  @override
  void dispose() {
    _handles.dispose();
    _legHandles.dispose();
    _places.dispose();
    _planner.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    _draw();
    _placeHandles();
  }

  /// The touch targets onto their points, after a change or a camera move.
  void _placeHandles() {
    final map = _map;
    // The style can finish loading after the screen has gone.
    if (!mounted || map == null || _style == null || _drag != null || _legDrag != null) return;
    final points = _planner.points;
    final legs = _planner.legs;
    final middles = [
      for (var i = 0; i + 1 < points.length && i < legs.length; i++)
        if (legs[i].leg?.line case final line? when line.isNotEmpty) line[line.length ~/ 2],
    ];
    try {
      final at = map.toScreenLocations([
        for (final p in points) Geographic(lon: p.lon, lat: p.lat),
        for (final m in middles) Geographic(lon: m[0], lat: m[1]),
      ]);
      _handles.value = at.take(points.length).toList();
      // Only while every leg between points is there: the dots keep their legs.
      _legHandles.value = middles.length == points.length - 1 ? at.skip(points.length).toList() : const [];
    } on Object {
      _handles.value = const []; // the map going away
      _legHandles.value = const [];
    }
  }

  /// Dragging leg [leg]: the other ways between its points show.
  void _legStart(int leg) {
    _legDrag = (leg: leg, at: _legHandles.value[leg], ways: null);
    _waysComing = _loadWays(leg);
  }

  Future<void> _loadWays(int leg) async {
    final from = _planner.points[leg], to = _planner.points[leg + 1];
    try {
      final ways = await widget.api.alternatives(
        (lon: from.lon, lat: from.lat),
        (lon: to.lon, lat: to.lat),
        profile: to.alpine ? 'alpine' : _planner.profile,
      );
      final drag = _legDrag;
      if (!mounted || drag == null || drag.leg != leg) return;
      final others = otherWays(ways, _planner.legs[leg].leg?.line ?? const []);
      final all = [for (final w in others) ...w.way];
      _waysOnScreen.clear();
      final map = _map;
      if (map != null && all.isNotEmpty) {
        for (final (i, o) in map.toScreenLocations([for (final p in all) Geographic(lon: p[0], lat: p[1])]).indexed) {
          _waysOnScreen[all[i]] = o;
        }
      }
      _legDrag = (leg: leg, at: drag.at, ways: others);
      _inReach = null;
      _showWays();
    } on Object {
      // none: a drop gives a stop
    }
  }

  void _legBy(int leg, Offset delta) {
    final drag = _legDrag;
    if (drag == null) return;
    _legDrag = (leg: leg, at: drag.at + delta, ways: drag.ways);
    _legHandles.value = [..._legHandles.value]..[leg] = drag.at + delta;
    final inReach = _nearWay(drag.at + delta)?.way.index;
    if (inReach != _inReach) {
      _inReach = inReach;
      _showWays();
    }
  }

  /// The other way within 40 px of [at], as on the website.
  ({({Way way, int index}) way, List<double> point, double px})? _nearWay(Offset at) {
    final ways = _legDrag?.ways ?? const [];
    if (ways.isEmpty || _waysOnScreen.isEmpty) return null;
    final hit = nearestWay(ways, at, (p) => _waysOnScreen[p] ?? const Offset(double.infinity, double.infinity));
    return hit != null && hit.px <= 40 ? hit : null;
  }

  /// The other ways while a leg is dragged, the one in reach stronger.
  void _showWays() {
    final ways = _legDrag?.ways ?? const [];
    final data = _waysJson([for (final w in ways) w.way], near: ways.indexWhere((w) => w.index == _inReach));
    _style?.updateGeoJsonSource(id: 'plan-alts', data: data).catchError((_) {});
  }

  /// Let go on another way: the leg takes it, through where it differs most
  /// from the rest; elsewhere a stop goes there (as «Zwischenpunkt» on the
  /// website, which has a switch for it).
  Future<void> _legDrop() async {
    // Let go before the ways came: they decide, so wait a moment for them.
    if (_legDrag case final d? when d.ways == null) {
      await _waysComing?.timeout(const Duration(seconds: 5), onTimeout: () {});
    }
    final drag = _legDrag;
    final map = _map;
    final hit = drag == null ? null : _nearWay(drag.at);
    _legDrag = null;
    _inReach = null;
    _waysOnScreen.clear();
    if (!mounted) return;
    _style?.updateGeoJsonSource(id: 'plan-alts', data: _waysJson(const [])).catchError((_) {});
    if (drag == null || map == null || drag.leg + 1 >= _planner.points.length) return _placeHandles();
    if (hit != null) {
      final rest = [
        for (final w in drag.ways ?? const <({Way way, int index})>[])
          if (!identical(w, hit.way)) w.way,
        ?_planner.legs[drag.leg].leg?.line,
      ];
      final p = distinctPoint(hit.way.way, rest);
      _planner.takeWay(drag.leg, (lon: p[0], lat: p[1]));
      return;
    }
    final where = map.toLngLat(drag.at);
    _planner.insertAt(drag.leg + 1, where.lon, where.lat);
  }

  /// [near]: the index of the way within reach.
  String _waysJson(List<Way> ways, {int? near}) => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final (i, w) in ways.indexed)
        {
          'type': 'Feature',
          'properties': {'near': i == near},
          'geometry': {'type': 'LineString', 'coordinates': w},
        },
    ],
  });

  void _dragBy(int index, Offset delta) {
    final at = (_drag?.at ?? _handles.value[index]) + delta;
    _drag = (index: index, at: at);
    _handles.value = [..._handles.value]..[index] = at;
    // The point follows the finger; the legs wait for the drop.
    final where = _map?.toLngLat(at);
    if (where != null) {
      _style
          ?.updateGeoJsonSource(
            id: 'plan-points',
            data: _pointsJson(moved: (index: index, lon: where.lon, lat: where.lat)),
          )
          .catchError((_) {});
    }
  }

  void _drop() {
    final drag = _drag;
    _drag = null;
    final where = drag == null ? null : _map?.toLngLat(drag.at);
    if (drag == null || where == null || drag.index >= _planner.points.length) return _placeHandles();
    _planner.move(_planner.points[drag.index].id, where.lon, where.lat);
  }

  Widget _buildMap() => LayoutBuilder(builder: (context, size) => _buildMapIn(context, size));

  Widget _buildMapIn(BuildContext context, BoxConstraints size) {
    // A route being changed, or a stage going on from the one before: there.
    final points = [
      for (final p in _planner.points) [p.lon, p.lat],
    ];
    final view = points.isEmpty
        ? (lon: 8.23, lat: 46.8, zoom: 7.0)
        : fitLine(points, size.maxWidth, size.maxHeight * (1 - PlanSheet.cover(context)), maxZoom: 13);
    return _mapLibre(view);
  }

  Widget _mapLibre(({double lon, double lat, double zoom}) view) => MapLibreMap(
    options: MapOptions(
      initStyle: swisstopoStyle(widget.api.server),
      initCenter: Geographic(lon: view.lon, lat: view.lat),
      initZoom: view.zoom,
    ),
    onEvent: (e) {
      _places.onEvent(e);
      switch (e) {
        case MapEventMapCreated(:final mapController):
          _map = mapController;
        case MapEventMoveCamera() || MapEventCameraIdle():
          _placeHandles();
        // Once the layers are there: before, a point could not be drawn.
        case MapEventClick(:final point, :final screenPoint) when _style != null:
          // A tap on a hut opens its sheet instead.
          final hut = _map?.featuresInRect(Rect.fromCircle(center: screenPoint, radius: 16), layerIds: ['places']);
          if (hut == null || hut.isEmpty) _planner.add(point.lon, point.lat);
        default:
      }
    },
    onStyleLoaded: (style) async {
      await _places.addTo(style);
      // The other ways while a leg is dragged, under the route.
      await style.addSource(GeoJsonSource(id: 'plan-alts', data: _waysJson(const [])));
      await style.addLayer(
        const LineStyleLayer(
          id: 'plan-alts',
          sourceId: 'plan-alts',
          // As on the website (RouteLayers.svelte).
          paint: {
            'line-color': '#0e7490',
            'line-width': [
              'case',
              ['get', 'near'],
              8,
              5,
            ],
            'line-opacity': [
              'case',
              ['get', 'near'],
              0.9,
              0.45,
            ],
          },
          layout: {'line-cap': 'round', 'line-join': 'round'},
        ),
      );
      await style.addSource(GeoJsonSource(id: 'plan-line', data: _lineJson()));
      await style.addLayer(
        const LineStyleLayer(
          id: 'plan-casing',
          sourceId: 'plan-line',
          paint: {'line-color': '#ffffff', 'line-width': 7},
          layout: {'line-cap': 'round', 'line-join': 'round'},
        ),
      );
      await style.addLayer(
        const LineStyleLayer(
          id: 'plan-route',
          sourceId: 'plan-line',
          paint: {'line-color': '#7e22ce', 'line-width': 4},
          layout: {'line-cap': 'round', 'line-join': 'round'},
        ),
      );
      await style.addSource(GeoJsonSource(id: 'plan-points', data: _pointsJson()));
      await style.addLayer(
        const CircleStyleLayer(
          id: 'plan-points',
          sourceId: 'plan-points',
          paint: {
            'circle-radius': 7,
            'circle-color': [
              'match',
              ['get', 'role'],
              'start',
              '#15803d',
              'end',
              '#b91c1c',
              '#7e22ce',
            ],
            'circle-stroke-color': '#ffffff',
            'circle-stroke-width': 2,
          },
        ),
      );
      await addProfilePoint(style);
      _style = style;
      _placeHandles();
    },
  );

  /// The sources exist once the style has loaded; updating one before crashes.
  void _draw() {
    final style = _style;
    if (style == null) return;
    style.updateGeoJsonSource(id: 'plan-line', data: _lineJson()).catchError((_) {});
    style.updateGeoJsonSource(id: 'plan-points', data: _pointsJson()).catchError((_) {});
  }

  String _lineJson() => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final leg in _planner.readyLegs)
        {
          'type': 'Feature',
          'properties': {},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final c in leg.line) [c[0], c[1]],
            ],
          },
        },
    ],
  });

  /// [moved]: a point being dragged, where the finger is.
  String _pointsJson({({int index, double lon, double lat})? moved}) {
    final points = _planner.points;
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        for (final (i, p) in points.indexed)
          {
            'type': 'Feature',
            'properties': {
              'role': i == 0
                  ? 'start'
                  : i == points.length - 1
                  ? 'end'
                  : 'via',
            },
            'geometry': {
              'type': 'Point',
              'coordinates': moved?.index == i ? [moved!.lon, moved.lat] : [p.lon, p.lat],
            },
          },
      ],
    });
  }

  void _showPlace(Pin pin) {
    final t = AppLocalizations.of(context);
    showPlace(
      context,
      pin,
      actions: [
        Builder(
          builder: (sheet) => FilledButton.icon(
            key: const Key('planner-add-place'),
            onPressed: () {
              Navigator.pop(sheet);
              _planner.add(pin.lon, pin.lat, name: pin.name);
            },
            icon: const Icon(Icons.add_location_alt_outlined),
            label: Text(t.plannerAddPlace),
          ),
        ),
      ],
    );
  }

  /// A searched place: added, and the map goes there.
  void _pick(FoundPlace p) {
    _planner.add(p.lon, p.lat, name: p.name);
    final map = _map;
    if (map == null) return;
    // From the second point on all of them, above the panel: the line in
    // view, to drag it.
    final points = _planner.points;
    if (points.length > 1) {
      // Not the map's size: under the search page with its keyboard the
      // planner is only a strip.
      final panel = MediaQuery.sizeOf(context).height * PlanSheet.cover(context);
      map
          .fitBounds(
            bounds: LngLatBounds.fromPoints([for (final q in points) Geographic(lon: q.lon, lat: q.lat)]),
            padding: EdgeInsets.fromLTRB(48, 48, 48, 48 + panel),
          )
          .catchError((_) {});
      return;
    }
    map
        .animateCamera(
          center: Geographic(lon: p.lon, lat: p.lat),
          zoom: max(map.getCamera().zoom, 12),
        )
        .catchError((_) {});
  }

  LonLat? _near() {
    final c = _map?.getCamera().center;
    return c == null ? null : (lon: c.lon, lat: c.lat);
  }

  Future<void> _save() async {
    if (_saving || !_planner.complete) return;
    final t = AppLocalizations.of(context);
    if (widget.edit != null || widget.stage != null) return _saveInto();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => _TitleDialog(initial: _planner.suggestedTitle),
    );
    if (title == null || title.trim().isEmpty || !mounted) return;
    setState(() => _saving = true);
    try {
      final route = await widget.api.createRoute(
        title: title.trim(),
        profile: _planner.profile,
        anchors: _planner.anchors,
        legs: _planner.readyLegs,
      );
      if (!mounted) return;
      // Opened like any saved route: to keep offline and to hike.
      final open = MaterialPageRoute<void>(
        builder: (_) => RouteScreen(api: widget.api, id: route.id, title: route.title),
      );
      if (widget.embedded) {
        await Navigator.of(context).push(open);
        widget.onSaved?.call();
      } else {
        widget.onSaved?.call();
        await Navigator.of(context).pushReplacement(open);
      }
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.plannerSaveFailed)));
    }
  }

  /// Into the route being changed, or the stage being planned; back with
  /// what was saved.
  Future<void> _saveInto() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final Object saved = switch ((widget.edit, widget.stage)) {
        (final r?, _) => await widget.api.updateRoute(r.id, r.version, {
          'profile': _planner.profile,
          'anchors': [for (final a in _planner.anchors) a.toJson()],
          'legs': [for (final l in _planner.readyLegs) l.json],
        }),
        (_, final st?) => await widget.api.createStageRoute(
          st.journeyId,
          st.stageId,
          profile: _planner.profile,
          anchors: _planner.anchors,
          legs: _planner.readyLegs,
        ),
        _ => throw StateError('nothing to save into'),
      };
      if (mounted) nav.pop(saved);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final conflict = e is ApiException && (e.status == 412 || e.status == 409);
      messenger.showSnackBar(SnackBar(content: Text(conflict ? t.saveConflict : t.plannerSaveFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(switch ((widget.edit, widget.stage)) {
                (final r?, _) => r.title,
                (_, final st?) => st.title,
                _ => t.plannerTitle,
              }),
            ),
      body: PlanSheet(
        map: Stack(
          children: [
            Positioned.fill(child: _mapView),
            Positioned.fill(
              child: ValueListenableBuilder(
                valueListenable: _handles,
                builder: (context, at, _) => Stack(
                  children: [
                    for (final (i, o) in at.indexed)
                      Positioned(
                        left: o.dx - 22,
                        top: o.dy - 22,
                        width: 44,
                        height: 44,
                        child: GestureDetector(
                          key: Key('planner-handle-$i'),
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: (d) => _dragBy(i, d.delta),
                          onPanEnd: (_) => _drop(),
                          onPanCancel: _drop,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: ValueListenableBuilder(
                valueListenable: _legHandles,
                builder: (context, at, _) => Stack(
                  children: [
                    for (final (i, o) in at.indexed)
                      Positioned(
                        left: o.dx - 22,
                        top: o.dy - 22,
                        width: 44,
                        height: 44,
                        child: GestureDetector(
                          key: Key('planner-leg-handle-$i'),
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (_) => _legStart(i),
                          onPanUpdate: (d) => _legBy(i, d.delta),
                          onPanEnd: (_) => _legDrop(),
                          onPanCancel: _legDrop,
                          child: Center(
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xff7e22ce), width: 3),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Positioned(top: 12, left: 12, right: 64, child: MapCorner(places: _places)),
            const Positioned(top: 12, right: 12, child: PlaceLayerButton()),
          ],
        ),
        panelKey: const Key('planner-panel'),
        children: _panel(t),
      ),
    );
  }

  List<Widget> _panel(AppLocalizations t) {
    final theme = Theme.of(context);
    final points = _planner.points;
    final legs = _planner.legs;
    final line = _planner.line;
    final totals = _planner.totals;
    return [
      SegmentedButton<String>(
        segments: [
          ButtonSegment(
            value: 'hike',
            label: Text(key: const Key('planner-hike'), t.plannerProfileHike),
          ),
          ButtonSegment(
            value: 'alpine',
            label: Text(key: const Key('planner-alpine'), t.plannerProfileAlpine),
          ),
        ],
        selected: {_planner.profile},
        showSelectedIcon: false,
        onSelectionChanged: (s) => _planner.setProfile(s.first),
      ),
      const SizedBox(height: 8),
      if (points.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(t.plannerHint)),
      for (final (i, p) in points.indexed) ...[
        ListTile(
          key: Key('planner-point-$i'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            i == 0
                ? Icons.trip_origin
                : i == points.length - 1
                ? Icons.place
                : Icons.more_vert,
          ),
          title: Text(p.name ?? t.plannerPointMap, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: Key('planner-up-$i'),
                tooltip: t.plannerUp,
                icon: const Icon(Icons.arrow_upward),
                onPressed: i == 0 ? null : () => _planner.reorder(i, i - 1),
              ),
              IconButton(
                key: Key('planner-down-$i'),
                tooltip: t.plannerDown,
                icon: const Icon(Icons.arrow_downward),
                onPressed: i == points.length - 1 ? null : () => _planner.reorder(i, i + 1),
              ),
              IconButton(
                key: Key('planner-remove-$i'),
                tooltip: t.plannerRemove,
                icon: const Icon(Icons.close),
                onPressed: () => _planner.remove(p.id),
              ),
            ],
          ),
        ),
        if (i < legs.length) _leg(t, i, legs[i]),
      ],
      if (_planner.roundTrip && points.length > 1)
        ListTile(
          key: const Key('planner-return'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.u_turn_left),
          title: Text(t.plannerReturn),
        ),
      // One search at a time (feedback issue 19): a destination, or with
      // «+ Zwischenziel» open a stop before it.
      if (!_via)
        PlaceSearch(
          api: widget.api,
          onPick: _pick,
          near: _near,
          label: switch (points.length) {
            0 => t.plannerSearchStart,
            1 => t.plannerSearchEnd,
            _ => t.plannerSearchMore,
          },
        )
      else
        PlaceSearch(
          key: const Key('planner-via-search'),
          api: widget.api,
          near: _near,
          label: t.plannerSearchVia,
          onPick: (p) {
            setState(() => _via = false);
            _planner.insertBeforeLast(p.lon, p.lat, name: p.name);
          },
        ),
      // On a narrow screen the round trip goes below.
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton(
            key: const Key('planner-via'),
            onPressed: points.length < 2 ? null : () => setState(() => _via = !_via),
            child: Text(_via ? t.cancel : '+ ${t.plannerVia}'),
          ),
          InkWell(
            onTap: () => _planner.setRoundTrip(!_planner.roundTrip),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  key: const Key('planner-round'),
                  value: _planner.roundTrip,
                  onChanged: (v) => _planner.setRoundTrip(v ?? false),
                ),
                Text(t.plannerRoundTrip),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
      if (line.length > 1) ...[
        const SizedBox(height: 16),
        Text(
          key: const Key('planner-totals'),
          '${formatDistance(totals.distanceM)} · ${formatDuration(totals.durationS, _pace)} · '
          '↑\u00a0${formatHeight(totals.ascentM)} ↓\u00a0${formatHeight(totals.descentM)} · '
          '${formatSac(totals.sacGrade, totals.sacMax)}',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ElevationProfile.ofLine(
          line,
          onPoint: (at) {
            if (_style case final style?) showProfilePoint(style, at).catchError((_) {});
          },
        ),
      ],
      if (points.length > 1) ...[
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('planner-save'),
          onPressed: _planner.complete && !_saving ? _save : null,
          icon: _saving
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: Text(t.plannerSave),
        ),
      ],
    ];
  }

  /// Between two points: computing, the leg's numbers, or why it failed.
  Widget _leg(AppLocalizations t, int i, LegSlot slot) {
    final theme = Theme.of(context);
    final Widget child;
    if (slot.leg case final leg?) {
      final small = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
      // None on a round trip's way back: it has no point of its own.
      final to = _planner.points.elementAtOrNull(i + 1);
      // «Wandern» goes round a harder part (as at Chamanna Jenatsch).
      final (note, action) = switch (leg.alpine) {
        _ when to == null => (null, null),
        final a? when !to.alpine => (
          '${t.plannerAlpineShorter(formatDistance(a.distanceM), formatDistance(leg.distanceM))}'
              '${a.sacGrade > 3 ? ' ${t.plannerAlpineGrade('T${a.sacGrade}')}' : ''}',
          TextButton(
            key: Key('planner-alpine-use-$i'),
            onPressed: () => _planner.setAlpine(i, true),
            child: Text(t.plannerAlpineUse),
          ),
        ),
        _ when to.alpine && _planner.profile == 'hike' => (
          t.plannerAlpineUsed,
          TextButton(
            key: Key('planner-alpine-undo-$i'),
            onPressed: () => _planner.setAlpine(i, false),
            child: Text(t.plannerAlpineUndo),
          ),
        ),
        _ => (null, null),
      };
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${formatDistance(leg.distanceM)} · ${formatDuration(leg.durationS, _pace)}', style: small),
          if (note != null) Text(key: Key('planner-alpine-$i'), note, style: small),
          ?action,
        ],
      );
    } else if (slot.error case final status?) {
      child = Row(
        children: [
          Expanded(
            child: Text(
              key: Key('planner-leg-error-$i'),
              status == 422 ? t.plannerLegNoPath : t.plannerLegFailed,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ),
          if (status != 422)
            TextButton(key: Key('planner-retry-$i'), onPressed: _planner.retry, child: Text(t.plannerRetry)),
        ],
      );
    } else {
      child = const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: LinearProgressIndicator());
    }
    return Padding(key: Key('planner-leg-$i'), padding: const EdgeInsets.only(left: 40), child: child);
  }
}

/// Asks for the route's title, prefilled from its points' names.
class _TitleDialog extends StatefulWidget {
  const _TitleDialog({required this.initial});
  final String initial;

  @override
  State<_TitleDialog> createState() => _TitleDialogState();
}

class _TitleDialogState extends State<_TitleDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.plannerSave),
      content: TextField(
        key: const Key('planner-title'),
        controller: _text,
        autofocus: true,
        decoration: InputDecoration(labelText: t.plannerRouteTitle),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        ValueListenableBuilder(
          valueListenable: _text,
          builder: (context, value, _) => FilledButton(
            key: const Key('planner-save-confirm'),
            // The text as it is when pressed, not as last drawn.
            onPressed: value.text.trim().isEmpty ? null : () => Navigator.pop(context, _text.text),
            child: Text(t.plannerSaveConfirm),
          ),
        ),
      ],
    );
  }
}
