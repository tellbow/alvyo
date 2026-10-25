import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import '../analytics.dart';
import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../map_credit.dart';
import '../map_style.dart';
import '../navigation/gps.dart';
import '../navigation/recording.dart';
import '../navigation/tracker.dart';
import '../offline/packs.dart';
import '../place_layer.dart';
import '../route_layers.dart';
import 'navigate_screen.dart';
import 'route_screen.dart';
import 'tiles.dart';

/// Recording a hike without a planned route (the record button): the
/// position and the track so far on the map, how far and how long. Once
/// uploaded, the hike is a route like any other.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.api, this.positions, this.recordings, this.map});

  final Api api;

  /// For tests: positions instead of the GPS, where recordings are kept,
  /// and what stands in for the map.
  final Stream<Fix> Function()? positions;
  final Directory? recordings;
  final Widget? map;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  Recording? _recording;

  /// The recording's positions, for the track and the numbers.
  final _fixes = <Fix>[];
  StreamSubscription<Fix>? _sub;
  MapController? _map;
  StyleController? _style;
  Fix? _fix;
  bool _follow = true;
  bool _denied = false;
  GpsProblem? _gps;
  bool _saveWarned = false; // said once that fixes cannot be saved
  bool _starting = false;
  static const _followZoom = 15.0;
  Timer? _clock;
  late final _places = PlaceLayer(widget.api, onTap: (p) => showPlace(context, p));

  /// The tour to follow (requirement 69): started on its page, as «Los».
  RouteSummary? _tour;

  /// One's routes not hiked yet and those shared, to follow; the saved ones
  /// without a connection.
  Future<void> _chooseTour() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // With the owner for shared ones.
    List<(RouteSummary, String?)> routes;
    try {
      final own = await widget.api.routes();
      final shared = await widget.api.shared().then((s) => s.routes, onError: (Object _) => <RouteSummary>[]);
      routes = [
        for (final r in own)
          if (r.doneOn == null) (r, null),
        for (final r in shared) (r, r.owner),
      ];
    } on Object {
      final saved = await (await PackStore.open()).savedRoutes().catchError((_) => <RouteDetail>[]);
      routes = [for (final r in saved) (r, null)];
    }
    if (!mounted) return;
    if (routes.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(t.recordNoTours)));
      return;
    }
    final picked = await showModalBottomSheet<RouteSummary>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scroll) => ListView(
          controller: scroll,
          children: [
            ListTile(title: Text(t.recordFollow, style: Theme.of(context).textTheme.titleMedium)),
            for (final (r, owner) in routes)
              RouteTile(
                key: Key('record-tour-${r.id}'),
                route: r,
                owner: owner,
                onTap: () => Navigator.pop(context, r),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _tour = picked);
  }

  /// Follows the chosen tour on its page, recording there.
  void _startTour(RouteSummary r) => Navigator.of(context).pushReplacement(
    MaterialPageRoute<HikeSummary>(
      builder: (_) => RouteScreen(api: widget.api, id: r.id, title: r.title, startHike: true),
    ),
  );

  late final Widget _mapView =
      widget.map ??
      MapLibreMap(
        options: MapOptions(
          initStyle: swisstopoStyle(widget.api.server),
          initCenter: const Geographic(lon: 8.23, lat: 46.8),
          initZoom: 7,
        ),
        onMapCreated: (c) => _map = c,
        onStyleLoaded: _onStyle,
        onEvent: (e) {
          _places.onEvent(e);
          if (e is MapEventStartMoveCamera && e.reason == CameraChangeReason.apiGesture && _follow) {
            setState(() => _follow = false);
          }
        },
      );

  @override
  void initState() {
    super.initState();
    Analytics.instance.screen('record');
    _listen();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {})); // elapsed time
  }

  /// The GPS from the start, so that the map shows where the hike begins;
  /// a hike without a route still being recorded goes on.
  Future<void> _listen() async {
    if (widget.positions == null && !await locationAllowed()) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    final root = widget.recordings ?? await Recording.defaultRoot();
    final rec = await Recording.active(root);
    if (rec != null && Recording.before(rec, null, widget.api.userId) == Before.resume) {
      _fixes.addAll(await rec.fixes());
      _recording = rec;
    }
    if (!mounted) return;
    setState(() {});
    _sub = (widget.positions ?? () => gpsFixes(AppLocalizations.of(context)))().listen(
      _onFix,
      onError: (Object e) {
        if (mounted) setState(() => _gps = gpsProblem(e));
      },
    );
  }

  Future<void> _start() async {
    if (_starting) return; // a double tap would start twice
    _starting = true;
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final Recording rec;
    try {
      final root = widget.recordings ?? await Recording.defaultRoot();
      // A route's hike or another account's: kept for uploading, this one
      // starts (the record button opens a route's hike instead).
      await (await Recording.active(root))?.finish();
      rec = await Recording.start(root, title: t.recordTitle, owner: widget.api.userId);
      if (_fix case final f?) await rec.add(f); // where it starts
    } on Object {
      // e.g. the phone's storage full: say so, and the button works again
      _starting = false;
      messenger.showSnackBar(SnackBar(content: Text(t.errorGeneric)));
      return;
    }
    if (!mounted) return;
    setState(() {
      _recording = rec;
      _fixes
        ..clear()
        ..addAll([?_fix]);
    });
  }

  /// Saving a fix failed (the phone's storage full): said once, the hike
  /// goes on.
  void _saveFailed() {
    if (_saveWarned || !mounted) return;
    _saveWarned = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).recordSaveFailed), duration: const Duration(seconds: 10)),
    );
  }

  Future<void> _onFix(Fix fix) async {
    final rec = _recording;
    if (rec != null) {
      try {
        await rec.add(fix);
      } on Object {
        _saveFailed();
      }
      _fixes.add(fix);
    }
    if (!mounted) return;
    setState(() {
      _fix = fix;
      _gps = null;
    });
    await _style?.updateGeoJsonSource(id: 'me', data: positionJson(fix.lon, fix.lat));
    if (rec != null) await _style?.updateGeoJsonSource(id: 'route', data: lineJson(_track()));
    if (_follow) {
      // The next position or a gesture can cut it short (Android then fails it).
      await _map
          ?.animateCamera(
            center: Geographic(lon: fix.lon, lat: fix.lat),
            zoom: _followZoom,
            nativeDuration: const Duration(milliseconds: 400),
          )
          .catchError((_) {});
    }
  }

  /// The track drawn: positions accurate to 30 m, like its length.
  List<List<double>> _track() => [
    for (final f in _fixes)
      if (f.accuracyM <= 30) [f.lon, f.lat],
  ];

  Future<void> _onStyle(StyleController style) async {
    await _places.addTo(style);
    await addRouteLine(style, _track());
    await addPositionDot(style, _fix?.lon, _fix?.lat);
    // Only now: a position coming in meanwhile would update the sources
    // before they exist (the iOS plugin fails on that).
    _style = style;
  }

  Future<void> _finish() async {
    final rec = _recording;
    if (rec == null) {
      Navigator.of(context).pop();
      return;
    }
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(t.navFinishQuestion),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.navContinue)),
          FilledButton(
            key: const Key('nav-finish-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.navFinish),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _sub?.cancel();
    _sub = null;
    final fixes = await rec.fixes();
    await rec.finish();
    final summary = HikeSummary(
      trackLengthM(fixes),
      fixes.isEmpty ? Duration.zero : fixes.last.time.difference(rec.started),
      rec.started.toIso8601String(),
    );
    if (mounted) Navigator.of(context).pop(summary);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _clock?.cancel();
    _places.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final rec = _recording;
    return PopScope(
      canPop: rec == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: rec == null
              ? CloseButton(key: const Key('record-close'), onPressed: () => Navigator.of(context).maybePop())
              : null,
          centerTitle: true,
          title: Text(t.navRecord),
          actions: [
            if (rec != null) TextButton(key: const Key('nav-finish'), onPressed: _finish, child: Text(t.navFinish)),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  _mapView,
                  Positioned(top: 12, left: 12, right: 64, child: MapCorner(places: _places)),
                  const Positioned(top: 12, right: 12, child: PlaceLayerButton()),
                  if (!_follow && _fix != null)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: FloatingActionButton.small(
                        key: const Key('nav-follow'),
                        tooltip: t.navFollow,
                        onPressed: () {
                          setState(() => _follow = true);
                          final f = _fix!;
                          _map
                              ?.animateCamera(
                                center: Geographic(lon: f.lon, lat: f.lat),
                                zoom: _followZoom,
                                nativeDuration: const Duration(milliseconds: 400),
                              )
                              .catchError((_) {});
                        },
                        child: const Icon(Icons.my_location),
                      ),
                    ),
                ],
              ),
            ),
            if (_gps case final problem?)
              Container(
                key: const Key('nav-gps-lost'),
                width: double.infinity,
                color: Theme.of(context).colorScheme.errorContainer,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(gpsText(t, problem), style: Theme.of(context).textTheme.titleSmall),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: _denied
                    ? Text(t.navNoPermission)
                    : rec == null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(t.recordFollow, style: Theme.of(context).textTheme.labelLarge),
                          const SizedBox(height: 6),
                          if (_tour case final r?)
                            RouteTile(key: const Key('record-tour'), route: r, onTap: _chooseTour)
                          else
                            OutlinedButton.icon(
                              key: const Key('record-tour'),
                              onPressed: _chooseTour,
                              icon: const Icon(Icons.route_outlined),
                              label: Text(t.recordChooseTour),
                            ),
                          if (_tour != null)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                key: const Key('record-tour-clear'),
                                onPressed: () => setState(() => _tour = null),
                                child: Text(t.recordWithoutTour),
                              ),
                            ),
                          const SizedBox(height: 8),
                          if (_fix == null && _tour == null) ...[Text(t.navWaiting), const SizedBox(height: 8)],
                          FilledButton.icon(
                            key: const Key('record-start'),
                            onPressed: switch (_tour) {
                              final r? => () => _startTour(r),
                              null => _start,
                            },
                            icon: const Icon(Icons.fiber_manual_record),
                            label: Text(t.recordStart),
                          ),
                        ],
                      )
                    : Row(
                        key: const Key('record-progress'),
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _Stat(t.navDone, formatDistance(trackLengthM(_fixes))),
                          _Stat(t.navElapsed, formatDuration(DateTime.now().difference(rec.started).inSeconds)),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(label, style: theme.labelMedium),
        Text(value, style: theme.titleMedium),
      ],
    );
  }
}
