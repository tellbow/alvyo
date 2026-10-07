import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import '../api.dart';
import '../route_layers.dart';
import '../format.dart';
import '../journey_ways.dart';
import '../l10n/app_localizations.dart';
import '../map_style.dart';
import '../place_layer.dart';
import '../place_search.dart';
import '../precip.dart';
import 'journey_screen.dart';
import 'plan_sheet.dart';
import 'travel_screen.dart';

/// Stage colours as on the website, cycled.
// As on the website: neighbours differ also for red-green colour blindness.

Color _color(String hex) => Color(int.parse('ff${hex.substring(1)}', radix: 16));

const _kinds = ['hut', 'hotel', 'campsite', 'pt_stop'];

enum _Problem { noPath, failed, create, tooLong }

/// «Etappentour planen», as on the website: start, points to pass and
/// destination, split into days that end at a place to stay; or several ways
/// to choose from, and a journey put together from them.
class JourneyPlanScreen extends StatefulWidget {
  const JourneyPlanScreen({super.key, required this.api, this.showMap = true, this.embedded = false, this.onSaved});
  final Api api;

  /// Inside Planen (requirement 69): without its app bar; a created journey
  /// is opened on top and [onSaved] called (the tab then starts anew).
  final bool embedded;
  final VoidCallback? onSaved;

  /// Off in widget tests: MapLibre does not render there.
  final bool showMap;

  @override
  State<JourneyPlanScreen> createState() => _JourneyPlanScreenState();
}

class _JourneyPlanScreenState extends State<JourneyPlanScreen> {
  late final _places = PlaceLayer(widget.api, onTap: (p) => showPlace(context, p));
  late final Widget _mapView = _buildMap();
  MapController? _map;
  StyleController? _style;

  /// Hours are shown and asked at the hiker's pace; the API counts Swiss
  /// hiking time.
  late final Future<double> _paceLoaded = widget.api.me().then((m) => m.speedFactor, onError: (_) => 1.0);
  double _pace = 1;

  /// Start, points to pass, destination: each new point is the destination.
  var _points = <({double lon, double lat, String? name})>[];

  /// Counts the changes of the points: answers for older points are dropped.
  int _asked = 0;

  var _byDays = true;
  final _days = TextEditingController(text: '3');
  final _maxHours = TextEditingController();
  final _minPerDay = TextEditingController(text: '4');
  final _maxPerDay = TextEditingController(text: '8');
  var _profile = 'hike';
  var _kindsWanted = {'hut', 'hotel'};

  /// The days shown.
  List<PlannedStage>? _stages;

  /// Suggested ways with their days, and the days of the journey put
  /// together from them.
  var _ways = <Suggestion>[];
  var _wayDays = <List<PlannedStage>>[];
  var _picked = <Picked>[];

  var _busy = false;
  _Problem? _problem;

  /// With [_Problem.tooLong]: the fewest days that fit (0: none do).
  var _fewest = 0;
  final _title = TextEditingController();

  @override
  void initState() {
    super.initState();
    _paceLoaded.then((p) {
      if (mounted) setState(() => _pace = p);
    });
  }

  @override
  void dispose() {
    _places.dispose();
    for (final c in [_days, _maxHours, _minPerDay, _maxPerDay, _title]) {
      c.dispose();
    }
    super.dispose();
  }

  List<List<String?>> get _nights => [
    for (final days in _wayDays) [for (final st in days) st.endPlace?.id],
  ];
  int? get _chosen => _ways.isEmpty ? null : single(_nights, _picked);
  bool get _mixed => _ways.isNotEmpty && _chosen == null;

  static double? _number(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  bool get _asksOk {
    if (_byDays) {
      final d = int.tryParse(_days.text.trim());
      final max = _maxHours.text.trim().isEmpty ? 1 : _number(_maxHours);
      return d != null && d >= 1 && d <= 60 && max != null && max > 0;
    }
    final min = _number(_minPerDay), max = _number(_maxPerDay);
    return min != null && max != null && min > 0 && min <= max;
  }

  /// The most per day as typed.
  String get _maxAsked => (_byDays ? _maxHours : _maxPerDay).text.trim();

  bool get _canPlan => !_busy && _points.length >= 2 && _asksOk;

  /// Days, or hours from … to, in Swiss hiking time.
  ({int? days, double? minHours, double? maxHours}) _split(double pace) {
    if (_byDays) {
      final max = _number(_maxHours);
      return (days: int.parse(_days.text.trim()), minHours: null, maxHours: max == null ? null : max / pace);
    }
    return (days: null, minHours: _number(_minPerDay)! / pace, maxHours: _number(_maxPerDay)! / pace);
  }

  List<String> get _kindList => [
    for (final k in _kinds)
      if (_kindsWanted.contains(k)) k,
  ];

  List<LonLat> get _lonLats => [for (final p in _points) (lon: p.lon, lat: p.lat)];

  void _reset() {
    _asked++;
    _stages = null;
    _ways = [];
    _wayDays = [];
    _picked = [];
    _problem = null;
  }

  void _addPoint(double lon, double lat, [String? name]) {
    setState(() {
      _points = [..._points, (lon: lon, lat: lat, name: name)];
      _reset();
      final start = _points.first.name;
      if (_title.text.isEmpty && _points.length >= 2 && start != null && name != null) {
        _title.text = '$start – $name';
      }
    });
    _draw();
  }

  void _removePoint(int i) {
    setState(() {
      _points = [..._points]..removeAt(i);
      _reset();
    });
    _draw();
  }

  void _addPlace(FoundPlace p) {
    _addPoint(p.lon, p.lat, p.name);
    final map = _map;
    if (map == null) return;
    map
        .animateCamera(
          center: Geographic(lon: p.lon, lat: p.lat),
          zoom: max(map.getCamera().zoom, 11),
          nativeDuration: const Duration(milliseconds: 600),
        )
        .catchError((_) {});
  }

  /// Runs a planning call; the answer is dropped when the points changed
  /// meanwhile (plan again).
  Future<void> _run<T>(
    Future<T> Function(({int? days, double? minHours, double? maxHours}) split) call,
    void Function(T answer) done,
  ) async {
    final asked = _asked;
    setState(() {
      _busy = true;
      _problem = null;
    });
    T? answer;
    _Problem? problem;
    try {
      answer = await call(_split(await _paceLoaded));
    } on ApiException catch (e) {
      problem = e.status == 422 ? _Problem.noPath : _Problem.failed;
      if (e.fewestDays case final n?) {
        problem = _Problem.tooLong;
        _fewest = n;
      }
    } on Object {
      problem = _Problem.failed;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (asked != _asked) return;
      if (problem != null) {
        // No days shown that cannot be hiked as asked.
        if (problem == _Problem.tooLong) _reset();
        _problem = problem;
      } else {
        done(answer as T);
      }
    });
    _draw();
  }

  /// Plans the days; with [ends], ends them there instead, along the way
  /// chosen if there are suggested ways.
  void _plan([List<String>? ends]) {
    final way = ends == null ? null : _chosen;
    _run(
      (s) => widget.api.planJourney(
        points: way == null ? _lonLats : _ways[way].points,
        profile: _profile,
        days: s.days,
        minHours: s.minHours,
        maxHours: s.maxHours,
        kinds: _kindList,
        ends: ends,
      ),
      (p) {
        if (way != null) {
          _wayDays[way] = p.stages;
          _picked = whole(_nights, way);
        } else {
          _ways = [];
          _wayDays = [];
          _picked = [];
        }
        _stages = p.stages;
        _fit();
      },
    );
  }

  void _suggest() => _run(
    (s) => widget.api.suggestJourneys(
      points: _lonLats,
      profile: _profile,
      days: s.days,
      minHours: s.minHours,
      maxHours: s.maxHours,
      kinds: _kindList,
    ),
    (ways) {
      if (ways.isEmpty) {
        _problem = _Problem.noPath;
        return;
      }
      _ways = ways;
      _wayDays = [for (final w in ways) w.proposal.stages];
      _pick(0);
    },
  );

  void _pick(int way) {
    _picked = whole(_nights, way);
    _stages = stagesOf(_wayDays, _picked);
    _fit();
  }

  void _choose(int way) {
    setState(() => _pick(way));
    _draw();
  }

  /// Goes on after day [i] along another way that sleeps at the same place.
  void _goOn(int i, Picked to) {
    setState(() {
      _picked = switchTo(_nights, _picked, i, to);
      _stages = stagesOf(_wayDays, _picked);
    });
    _draw();
  }

  /// Ends day [i] at another place; the other nights stay where they are.
  void _endAt(int i, String placeId) {
    final stages = _stages!;
    final ends = [for (final st in stages.take(stages.length - 1)) st.endPlace!.id];
    ends[i] = placeId;
    _plan(ends);
  }

  /// From and to which home by public transport, saved with the journey.
  var _travel = const Travel();

  Future<void> _create() async {
    final stages = _stages;
    if (stages == null) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final j = await widget.api.createJourney(title: _title.text.trim(), stages: stages);
      final travel = _travel;
      if (travel.to != null || travel.back != null) {
        // The journey is there anyway: a failure here is not worth an error.
        await widget.api.setTravel(j.id, travel).catchError((_) => travel);
      }
      if (!mounted) return;
      final open = MaterialPageRoute<void>(
        builder: (_) => JourneyScreen(api: widget.api, id: j.id, title: j.title),
      );
      if (widget.embedded) {
        await Navigator.of(context).push(open);
        widget.onSaved?.call();
      } else {
        await Navigator.of(context).pushReplacement(open);
      }
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _problem = _Problem.create;
      });
    }
  }

  // The map.

  Widget _buildMap() => MapLibreMap(
    options: MapOptions(
      initStyle: swisstopoStyle(widget.api.server),
      initCenter: Geographic(lon: 8.23, lat: 46.8),
      initZoom: 6.8,
    ),
    onMapCreated: (c) => _map = c,
    onEvent: (e) {
      _places.onEvent(e);
      if (e case MapEventClick(:final point, :final screenPoint)) _tapped(point, screenPoint);
    },
    onStyleLoaded: (style) async {
      await _places.addTo(style);
      await style.addSource(GeoJsonSource(id: 'jplan-ways', data: _waysJson()));
      await style.addSource(GeoJsonSource(id: 'jplan-days', data: _daysJson()));
      await style.addSource(GeoJsonSource(id: 'jplan-points', data: _pointsJson()));
      const round = {'line-cap': 'round', 'line-join': 'round'};
      await style.addLayer(
        const LineStyleLayer(
          id: 'jplan-ways',
          sourceId: 'jplan-ways',
          paint: {'line-color': '#a8a29e', 'line-width': 4},
          layout: round,
        ),
      );
      await style.addLayer(
        const LineStyleLayer(
          id: 'jplan-days-casing',
          sourceId: 'jplan-days',
          paint: {'line-color': '#ffffff', 'line-width': 7},
          layout: round,
        ),
      );
      await style.addLayer(
        const LineStyleLayer(
          id: 'jplan-days',
          sourceId: 'jplan-days',
          paint: {
            'line-color': ['get', 'color'],
            'line-width': 4,
          },
          layout: round,
        ),
      );
      await style.addLayer(
        const CircleStyleLayer(
          id: 'jplan-points',
          sourceId: 'jplan-points',
          paint: {
            'circle-radius': 7,
            'circle-color': [
              'match',
              ['get', 'kind'],
              'start',
              '#16a34a',
              'end',
              '#a21caf',
              '#ffffff',
            ],
            'circle-stroke-color': [
              'match',
              ['get', 'kind'],
              'via',
              '#a21caf',
              '#ffffff',
            ],
            'circle-stroke-width': 3,
          },
        ),
      );
      _style = style;
      _draw(); // changed while the layers were added
    },
  );

  /// A tap on a place opens it (the place layer), on a way not chosen
  /// chooses it, elsewhere adds a point.
  void _tapped(Geographic at, Offset screen) {
    final map = _map;
    if (map == null || _style == null) return;
    final near = Rect.fromCircle(center: screen, radius: 16);
    if (map.featuresInRect(near, layerIds: ['places']).isNotEmpty) return;
    final way = map.featuresInRect(near, layerIds: ['jplan-ways']).firstOrNull?.properties['way'];
    if (way is num) {
      if (!_busy && way.toInt() < _ways.length) _choose(way.toInt());
      return;
    }
    _addPoint(at.lon, at.lat);
  }

  void _draw() {
    final style = _style;
    if (style == null) return;
    style.updateGeoJsonSource(id: 'jplan-ways', data: _waysJson()).catchError((_) {});
    style.updateGeoJsonSource(id: 'jplan-days', data: _daysJson()).catchError((_) {});
    style.updateGeoJsonSource(id: 'jplan-points', data: _pointsJson()).catchError((_) {});
  }

  static Map<String, dynamic> _lineFeature(List<List<double>> line, Map<String, Object> properties) => {
    'type': 'Feature',
    'properties': properties,
    'geometry': {
      'type': 'LineString',
      'coordinates': [
        for (final c in line) [c[0], c[1]],
      ],
    },
  };

  static String _collection(List<Map<String, dynamic>> features) =>
      jsonEncode({'type': 'FeatureCollection', 'features': features});

  /// The ways not taken, grey below the days.
  String _waysJson() {
    final chosen = _chosen;
    return _collection([
      for (final (k, days) in _wayDays.indexed)
        if (k != chosen)
          for (final st in days) _lineFeature(st.line, {'way': k}),
    ]);
  }

  String _daysJson() => _collection([
    for (final (i, st) in (_stages ?? const <PlannedStage>[]).indexed)
      _lineFeature(st.line, {'color': stageColors[i % stageColors.length]}),
  ]);

  String _pointsJson() => _collection([
    for (final (i, p) in _points.indexed)
      {
        'type': 'Feature',
        'properties': {
          'kind': i == 0
              ? 'start'
              : i == _points.length - 1
              ? 'end'
              : 'via',
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [p.lon, p.lat],
        },
      },
  ]);

  void _fit() {
    final map = _map;
    final pts = [for (final st in _stages ?? const <PlannedStage>[]) ...st.line];
    if (map == null || pts.isEmpty) return;
    map
        .fitBounds(
          bounds: LngLatBounds(
            longitudeWest: pts.map((c) => c[0]).reduce(min),
            longitudeEast: pts.map((c) => c[0]).reduce(max),
            latitudeSouth: pts.map((c) => c[1]).reduce(min),
            latitudeNorth: pts.map((c) => c[1]).reduce(max),
          ),
          padding: EdgeInsets.fromLTRB(40, 40, 40, 40 + (context.size?.height ?? 0) * PlanSheet.initial),
          nativeDuration: const Duration(milliseconds: 600),
        )
        .catchError((_) {});
  }

  LonLat? _center() {
    final c = _map?.getCamera().center;
    return c == null ? null : (lon: c.lon, lat: c.lat);
  }

  // The panel.

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: Text(t.jplanTitle)),
      body: Stack(
        children: [
          if (widget.showMap) ...[
            Positioned.fill(child: _mapView),
            Positioned(top: 12, left: 12, right: 64, child: PrecipBar(controller: _places.precip)),
            const Positioned(top: 12, right: 12, child: PlaceLayerButton()),
          ] else
            const Positioned.fill(child: ColoredBox(color: Colors.black12)),
          PlanSheet(
            panelKey: const Key('jplan-panel'),
            children: [
              Text(t.jplanIntro, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              ..._pointList(t),
              PlaceSearch(
                api: widget.api,
                onPick: _addPlace,
                near: _center,
                label: switch (_points.length) {
                  0 => t.jplanSearchStart,
                  1 => t.jplanSearchEnd,
                  _ => t.jplanSearchMore,
                },
              ),
              if (_points.length < 2 && widget.showMap)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(t.jplanMapHint, style: Theme.of(context).textTheme.bodySmall),
                ),
              const SizedBox(height: 16),
              ..._asks(t),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('jplan-submit'),
                onPressed: _canPlan ? _plan : null,
                child: Text(_busy ? t.jplanRunning : t.jplanSubmit),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('jplan-suggest'),
                onPressed: _canPlan ? _suggest : null,
                child: Text(t.jplanSuggest),
              ),
              if (_busy) const LinearProgressIndicator(key: Key('jplan-busy')),
              if (_problem case final p?)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(key: const Key('jplan-problem'), switch (p) {
                    _Problem.noPath => t.jplanNoPath,
                    _Problem.failed => t.jplanFailed,
                    _Problem.create => t.errorServer,
                    _Problem.tooLong when _fewest > 0 => t.jplanTooLong(_maxAsked, _fewest),
                    _Problem.tooLong => t.jplanTooLongNone(_maxAsked),
                  }, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              if (_problem == _Problem.tooLong && _byDays && _fewest > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('jplan-fewest'),
                    onPressed: _busy
                        ? null
                        : () {
                            _days.text = '$_fewest';
                            _plan();
                          },
                    child: Text(t.jplanPlanIn(_fewest)),
                  ),
                ),
              if (_ways.isNotEmpty) ..._wayList(t),
              if (_stages case final stages?) ..._dayList(t, stages),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _pointList(AppLocalizations t) => [
    for (final (i, p) in _points.indexed)
      ListTile(
        key: Key('jplan-point-$i'),
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: _pointMark(i),
        title: Text(p.name ?? t.jplanPointMap),
        trailing: IconButton(
          key: Key('jplan-remove-$i'),
          tooltip: t.jplanPointRemove,
          icon: const Icon(Icons.close),
          onPressed: () => _removePoint(i),
        ),
      ),
  ];

  Widget _pointMark(int i) {
    final last = i == _points.length - 1;
    const purple = Color(0xffa21caf);
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: i == 0
            ? const Color(0xff16a34a)
            : last
            ? purple
            : Colors.white,
        border: Border.all(color: i == 0 || last ? Colors.white : purple, width: 3),
      ),
      child: i == 0 || last ? null : Text('$i', style: const TextStyle(fontSize: 9, color: purple)),
    );
  }

  static void _closeKeyboard(PointerDownEvent _) => FocusManager.instance.primaryFocus?.unfocus();

  Widget _numberField(Key key, TextEditingController c, String label) => TextField(
    key: key,
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    // The number pad has no key to close it and covers the buttons below.
    onTapOutside: _closeKeyboard,
    decoration: InputDecoration(labelText: label, isDense: true),
    onChanged: (_) => setState(() {}),
  );

  List<Widget> _asks(AppLocalizations t) {
    final theme = Theme.of(context);
    return [
      Text(t.jplanBy, style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(value: true, label: Text(t.jplanByDays, key: const Key('jplan-by-days'))),
          ButtonSegment(value: false, label: Text(t.jplanByHours, key: const Key('jplan-by-hours'))),
        ],
        selected: {_byDays},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => _byDays = s.first),
      ),
      const SizedBox(height: 8),
      if (_byDays)
        Row(
          spacing: 12,
          children: [
            SizedBox(width: 80, child: _numberField(const Key('jplan-days'), _days, t.jplanDays)),
            Expanded(child: _numberField(const Key('jplan-max'), _maxHours, t.jplanMax)),
          ],
        )
      else
        Row(
          spacing: 12,
          children: [
            Expanded(child: _numberField(const Key('jplan-hours-min'), _minPerDay, t.jplanHoursMin)),
            Expanded(child: _numberField(const Key('jplan-hours-max'), _maxPerDay, t.jplanHoursMax)),
          ],
        ),
      const SizedBox(height: 16),
      Text(t.jplanKinds, style: theme.textTheme.titleSmall),
      Wrap(
        spacing: 8,
        children: [
          for (final (kind, label) in [
            ('hut', t.jplanKindHut),
            ('hotel', t.jplanKindHotel),
            ('campsite', t.jplanKindCampsite),
            ('pt_stop', t.jplanKindPtStop),
          ])
            FilterChip(
              key: Key('jplan-kind-$kind'),
              label: Text(label),
              selected: _kindsWanted.contains(kind),
              onSelected: (on) => setState(() {
                _kindsWanted = on ? {..._kindsWanted, kind} : ({..._kindsWanted}..remove(kind));
              }),
            ),
        ],
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        key: const Key('jplan-profile'),
        initialValue: _profile,
        decoration: InputDecoration(labelText: t.jplanProfile),
        items: [
          DropdownMenuItem(value: 'hike', child: Text(t.jplanProfileHike)),
          DropdownMenuItem(value: 'alpine', child: Text(t.jplanProfileAlpine)),
        ],
        onChanged: (v) => setState(() => _profile = v ?? 'hike'),
      ),
    ];
  }

  String _wayName(AppLocalizations t, int k) =>
      _ways[k].via.isEmpty ? t.jplanWayDirect(k + 1) : t.jplanWayVia(k + 1, _ways[k].via);

  static double _distance(List<PlannedStage> stages) => stages.fold(0.0, (sum, st) => sum + st.totals.distanceM);

  List<Widget> _wayList(AppLocalizations t) {
    final chosen = _chosen;
    final theme = Theme.of(context);
    return [
      const SizedBox(height: 16),
      Text(t.jplanWays, style: theme.textTheme.titleSmall),
      for (final (k, days) in _wayDays.indexed)
        Card(
          key: Key('jplan-way-$k'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: chosen == k ? theme.colorScheme.onSurface : theme.dividerColor),
          ),
          child: ListTile(
            selected: chosen == k,
            title: Text(_wayName(t, k)),
            subtitle: Text(
              '${t.jplanSummary(days.length, formatDistance(_distance(days)))}\n'
              '${[for (final st in days) ?st.endPlace?.name].join(' · ')}',
            ),
            onTap: _busy ? null : () => _choose(k),
          ),
        ),
      if (_ways.length > 1) Text(t.jplanWaysHint, style: theme.textTheme.bodySmall),
    ];
  }

  List<Widget> _dayList(AppLocalizations t, List<PlannedStage> stages) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final warn = small?.copyWith(color: Colors.amber.shade900);
    final mixed = _mixed;
    return [
      const SizedBox(height: 16),
      Text(
        key: const Key('jplan-summary'),
        t.jplanSummary(stages.length, formatDistance(_distance(stages))),
        style: theme.textTheme.titleMedium,
      ),
      for (final (i, st) in stages.indexed)
        Card(
          key: Key('jplan-stage-$i'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Row(
                  spacing: 8,
                  children: [
                    CircleAvatar(radius: 6, backgroundColor: _color(stageColors[i % stageColors.length])),
                    Text(t.jplanDay(i + 1), style: const TextStyle(fontWeight: FontWeight.w600)),
                    Expanded(
                      child: Text(
                        '${formatDistance(st.totals.distanceM)} · ${formatDuration(st.totals.durationS, _pace)} · '
                        '↑\u00a0${formatHeight(st.totals.ascentM)} · ${formatSac(st.totals.sacGrade, st.totals.sacMax)}',
                        textAlign: TextAlign.end,
                        style: small,
                      ),
                    ),
                  ],
                ),
                Text(
                  key: Key('jplan-end-$i'),
                  '→ ${st.endPlace?.name ?? t.jplanToEnd}${mixed ? ' · ${t.jplanWay(_picked[i].way + 1)}' : ''}',
                ),
                // No launcher plugin in the app: the address to copy.
                if (webLink(st.endPlace?.website ?? '') case final link?)
                  SelectableText('${t.jplanWebsite}: $link', style: small),
                if (st.endPlace?.kind == 'hut') Text(t.jplanHutHint, style: warn),
                if (st.overMax)
                  Text(t.jplanOverMax, style: warn)
                else if (st.underMin)
                  Text(t.jplanUnderMin, style: warn),
                // A journey put together cannot move its nights one by one.
                if (!mixed && (st.earlier != null || st.later != null))
                  Wrap(
                    spacing: 8,
                    children: [
                      if (st.earlier case final e?)
                        TextButton(
                          key: Key('jplan-earlier-$i'),
                          onPressed: _busy ? null : () => _endAt(i, e.id),
                          child: Text(t.jplanEarlier(e.name)),
                        ),
                      if (st.later case final l?)
                        TextButton(
                          key: Key('jplan-later-$i'),
                          onPressed: _busy ? null : () => _endAt(i, l.id),
                          child: Text(t.jplanLater(l.name)),
                        ),
                    ],
                  ),
                if (_ways.length > 1)
                  for (final to in switches(_nights, _picked, i))
                    TextButton(
                      key: Key('jplan-switch-$i-${to.way}'),
                      onPressed: _busy ? null : () => _goOn(i, to),
                      child: Text(t.jplanSwitch(to.way + 1)),
                    ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 16),
      TextField(
        key: const Key('jplan-title'),
        controller: _title,
        maxLength: 120,
        onTapOutside: _closeKeyboard,
        decoration: InputDecoration(labelText: t.jplanTitleField),
        onChanged: (_) => setState(() {}),
      ),
      TravelChoice(api: widget.api, onChanged: (t) => _travel = t),
      FilledButton(
        key: const Key('jplan-create'),
        onPressed: _busy || _title.text.trim().isEmpty ? null : _create,
        child: Text(t.jplanCreate),
      ),
    ];
  }
}
