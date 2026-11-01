import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import '../api.dart';
import '../camera.dart';
import '../elevation_profile.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../map_credit.dart';
import '../map_style.dart';
import '../route_layers.dart';
import 'journey_screen.dart';

/// The map of lines (a file's tracks or the stages), each in its stage's
/// colour; [onTap] with the line and the point of it nearest to a tap on it.
class StageMap extends StatefulWidget {
  const StageMap({super.key, required this.api, required this.lines, this.onTap});
  final Api api;
  final List<List<List<double>>> lines;
  final void Function(int line, double lon, double lat)? onTap;

  @override
  State<StageMap> createState() => _StageMapState();
}

class _StageMapState extends State<StageMap> {
  MapController? _map;
  StyleController? _style;

  String get _json => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final (i, l) in widget.lines.indexed)
        {
          'type': 'Feature',
          'properties': {'color': stageColors[i % stageColors.length]},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final c in l) [c[0], c[1]],
            ],
          },
        },
    ],
  });

  @override
  void didUpdateWidget(StageMap old) {
    super.didUpdateWidget(old);
    if (!identical(old.lines, widget.lines)) {
      _style?.updateGeoJsonSource(id: 'stage-lines', data: _json).catchError((_) {});
    }
  }

  void _tapped(Geographic at, Offset screen) {
    final map = _map;
    final onTap = widget.onTap;
    if (map == null || onTap == null || _style == null) return;
    final near = Rect.fromCircle(center: screen, radius: 16);
    if (map.featuresInRect(near, layerIds: ['stage-lines']).isEmpty) return;
    var best = double.infinity;
    (int, List<double>)? found;
    final scale = cos(at.lat * pi / 180); // a degree of longitude is shorter
    for (final (k, l) in widget.lines.indexed) {
      for (final c in l) {
        final dx = (c[0] - at.lon) * scale;
        final dy = c[1] - at.lat;
        final d = dx * dx + dy * dy;
        if (d < best) {
          best = d;
          found = (k, c);
        }
      }
    }
    if (found case (final k, final c)) onTap(k, c[0], c[1]);
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      LayoutBuilder(
        builder: (context, size) {
          final view = fitLine([for (final l in widget.lines) ...l], size.maxWidth, size.maxHeight);
          return MapLibreMap(
            options: MapOptions(
              initStyle: swisstopoStyle(widget.api.server),
              initCenter: Geographic(lon: view.lon, lat: view.lat),
              initZoom: view.zoom,
            ),
            onMapCreated: (c) => _map = c,
            onEvent: (e) {
              if (e case MapEventClick(:final point, :final screenPoint)) _tapped(point, screenPoint);
            },
            onStyleLoaded: (style) async {
              await style.addSource(GeoJsonSource(id: 'stage-lines', data: _json));
              const round = {'line-cap': 'round', 'line-join': 'round'};
              await style.addLayer(
                const LineStyleLayer(
                  id: 'stage-lines-casing',
                  sourceId: 'stage-lines',
                  paint: {'line-color': '#ffffff', 'line-width': 7},
                  layout: round,
                ),
              );
              await style.addLayer(
                const LineStyleLayer(
                  id: 'stage-lines',
                  sourceId: 'stage-lines',
                  paint: {
                    'line-color': ['get', 'color'],
                    'line-width': 4,
                  },
                  layout: round,
                ),
              );
              _style = style;
              style.updateGeoJsonSource(id: 'stage-lines', data: _json).catchError((_) {}); // changed meanwhile
            },
          );
        },
      ),
      const Positioned(left: 4, bottom: 4, child: MapCredit()),
    ],
  );
}

/// «In Etappen aufteilen» (feedback issue 47): a line, of a file or a route,
/// split into days. Each end moves to a place before or after it, a tap on the
/// map or the profile adds one, and the journey is made only when asked.
class StageSplitScreen extends StatefulWidget {
  const StageSplitScreen({
    super.key,
    required this.api,
    required this.line,
    required this.title,
    required this.durationS,
    required this.propose,
    this.intro,
    this.nights = 0,
    this.onSaved,
    this.showMap = true,
  });
  final Api api;

  /// The whole line, shown before anything is proposed.
  final List<List<double>> line;
  final String title;

  /// Swiss hiking time of the whole line, for the days first offered.
  final int durationS;

  /// Nights of a recording: as many stages as days split there.
  final int nights;
  final String? intro;

  /// Widget tests have no native map.
  final bool showMap;

  /// Asks for the stages: [days] of them, ending at [ends] if given (place
  /// ids or `@lon/lat`).
  final Future<Proposal> Function(int days, List<String>? ends) propose;
  final VoidCallback? onSaved;

  @override
  State<StageSplitScreen> createState() => _StageSplitScreenState();
}

class _StageSplitScreenState extends State<StageSplitScreen> {
  static const _hoursPerDay = 6;

  late final _title = TextEditingController(text: widget.title);
  late final _days = TextEditingController(
    text: '${widget.nights > 0 ? widget.nights + 1 : max(2, (widget.durationS / 3600 / _hoursPerDay).round())}',
  );
  Proposal? _proposal;
  bool _busy = false;
  bool _failed = false;
  double _pace = 1;

  @override
  void initState() {
    super.initState();
    widget.api.me().then((u) {
      if (mounted) setState(() => _pace = u.speedFactor);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _title.dispose();
    _days.dispose();
    super.dispose();
  }

  /// Where the days end, as the API takes them.
  List<String> get _ends => [
    for (final st in _proposal!.stages.take(_proposal!.stages.length - 1))
      st.endPlace?.id ?? '@${st.line.last[0]}/${st.line.last[1]}',
  ];

  Future<void> _ask(int days, List<String>? ends) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final p = await widget.propose(days, ends);
      if (!mounted) return;
      _days.text = '${p.stages.length}';
      setState(() {
        _proposal = p;
        _busy = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  void _endsChanged(List<String> ends) => _ask(ends.length + 1, ends);

  void _split(int stage, double lon, double lat) {
    if (_busy || _proposal == null) return;
    _endsChanged([..._ends]..insert(stage, '@$lon/$lat'));
  }

  /// A tap [m] metres along the profile: in which stage, and where.
  void _tapProfile(double m, List<List<double>> line) {
    final p = _proposal;
    if (p == null) return;
    final at = pointAt(cumulativeM(line), line, m);
    var rest = m;
    for (final (k, st) in p.stages.indexed) {
      final length = cumulativeM(st.line).last;
      if (rest <= length || k == p.stages.length - 1) return _split(k, at.lon, at.lat);
      rest -= length;
    }
  }

  Future<void> _create() async {
    final p = _proposal;
    if (p == null) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final title = _title.text.trim();
      final j = await widget.api.createJourney(title: title.isEmpty ? widget.title : title, stages: p.stages);
      widget.onSaved?.call();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => JourneyScreen(api: widget.api, id: j.id, title: j.title),
        ),
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final p = _proposal;
    final small = Theme.of(context).textTheme.bodySmall;
    final line = p == null ? widget.line : [for (final st in p.stages) ...st.line];
    final lines = p == null ? [widget.line] : [for (final st in p.stages) st.line];
    final breaks = <int>[];
    var at = 0;
    for (final l in lines) {
      breaks.add(at);
      at += l.length;
    }
    return Scaffold(
      appBar: AppBar(title: Text(t.routeSplit)),
      body: Column(
        children: [
          if (widget.showMap)
            SizedBox(
              height: 240,
              child: StageMap(api: widget.api, lines: lines, onTap: p == null ? null : _split),
            ),
          if (_busy) const LinearProgressIndicator(key: Key('stages-busy')),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (line.any((c) => c.length > 2 && c[2] != 0))
                  ElevationProfile.ofLine(
                    line,
                    breaks: breaks,
                    onTapAt: p == null ? null : (m) => _tapProfile(m, line),
                  ),
                if (widget.intro case final intro?) Padding(padding: const EdgeInsets.only(top: 8), child: Text(intro)),
                const SizedBox(height: 8),
                Row(
                  spacing: 12,
                  children: [
                    SizedBox(
                      width: 80,
                      child: TextField(
                        key: const Key('stages-days'),
                        controller: _days,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: t.jplanDays),
                      ),
                    ),
                    Expanded(
                      child: FilledButton(
                        key: const Key('stages-propose'),
                        onPressed: _busy
                            ? null
                            : () {
                                final days = int.tryParse(_days.text.trim());
                                if (days != null && days >= 2 && days <= 60) _ask(days, null);
                              },
                        child: Text(t.jplanSubmit),
                      ),
                    ),
                  ],
                ),
                if (_failed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      key: const Key('stages-problem'),
                      t.jplanFailed,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                if (p != null) ...[
                  const SizedBox(height: 12),
                  Text(key: const Key('stages-hint'), t.stagesPickHint, style: small),
                  for (final (i, st) in p.stages.indexed)
                    Card(
                      key: Key('stages-stage-$i'),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 4,
                          children: [
                            Row(
                              spacing: 8,
                              children: [
                                CircleAvatar(
                                  radius: 6,
                                  backgroundColor: Color(
                                    int.parse('ff${stageColors[i % stageColors.length].substring(1)}', radix: 16),
                                  ),
                                ),
                                Text(t.jplanDay(i + 1), style: const TextStyle(fontWeight: FontWeight.w600)),
                                Expanded(
                                  child: Text(
                                    '${formatDistance(st.totals.distanceM)} · '
                                    '${formatDuration(st.totals.durationS, _pace)} · '
                                    '↑ ${formatHeight(st.totals.ascentM)}',
                                    textAlign: TextAlign.end,
                                    style: small,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              key: Key('stages-end-$i'),
                              '→ ${st.endPlace?.name ?? (i == p.stages.length - 1 ? t.jplanToEnd : t.stagesEndAt(formatDistance(p.stages.take(i + 1).fold(0.0, (m, s) => m + s.totals.distanceM))))}',
                            ),
                            if (i < p.stages.length - 1)
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (st.earlier case final e?)
                                    TextButton(
                                      key: Key('stages-earlier-$i'),
                                      onPressed: _busy ? null : () => _endsChanged(_ends..[i] = e.id),
                                      child: Text(t.jplanEarlier(e.name)),
                                    ),
                                  if (st.later case final l?)
                                    TextButton(
                                      key: Key('stages-later-$i'),
                                      onPressed: _busy ? null : () => _endsChanged(_ends..[i] = l.id),
                                      child: Text(t.jplanLater(l.name)),
                                    ),
                                  if (p.stages.length > 2)
                                    TextButton(
                                      key: Key('stages-merge-$i'),
                                      onPressed: _busy ? null : () => _endsChanged(_ends..removeAt(i)),
                                      child: Text(t.stagesMerge),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('stages-title'),
                    controller: _title,
                    maxLength: 120,
                    decoration: InputDecoration(labelText: t.jplanTitleField),
                  ),
                  FilledButton(
                    key: const Key('stages-create'),
                    onPressed: _busy ? null : _create,
                    child: Text(t.jplanCreate),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
