import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre/maplibre.dart';

import '../analytics.dart';
import '../api.dart';
import '../camera.dart';
import '../elevation_profile.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../map_credit.dart';
import '../map_style.dart';
import '../navigation/alerts.dart';
import '../navigation/gps.dart';
import '../navigation/live.dart';
import '../navigation/recording.dart';
import '../navigation/speech.dart';
import '../navigation/tracker.dart';
import '../navigation/turns.dart';
import '../navigation/watch.dart';
import '../offline/packs.dart';
import '../place_layer.dart';
import '../route_layers.dart';

/// What was recorded, for the screen that started the hike to show.
class HikeSummary {
  const HikeSummary(this.distanceM, this.duration, this.id);
  final double distanceM;
  final Duration duration;

  /// The hike's id when uploaded (see uploadHikes).
  final String id;

  /// What became of it, from what uploadHikes returned: saved as a route,
  /// refused by the server, or waiting to be uploaded.
  String message(AppLocalizations t, Map<String, String?> routes) {
    final distance = formatDistance(distanceM), time = formatDuration(duration.inSeconds);
    if (!routes.containsKey(id)) return t.navSaved(distance, time);
    return routes[id] != null ? t.navUploaded(distance, time) : t.recordRefused;
  }
}

/// Hiking a route: the position on the (offline) map, how far it is still,
/// the next turn, spoken too, a warning when leaving the route, and a
/// recording of the hike.
class NavigateScreen extends StatefulWidget {
  /// The route's name on the navigator, to go back to a hike running.
  static const routeName = 'navigate';

  /// A hike is being navigated and recorded: there is one at a time.
  static bool running = false;

  const NavigateScreen({
    super.key,
    required this.api,
    required this.route,
    this.pack,
    this.turns,
    this.positions,
    this.recordings,
    this.alerts,
    this.speech,
    this.live,
    this.watch,
  });

  final Api api;
  final RouteDetail route;

  /// The saved offline map, if any.
  final SavedPack? pack;

  /// The turns saved with it; else they are asked for online.
  final List<Turn>? turns;

  /// For tests: positions instead of the GPS.
  final Stream<Fix> Function()? positions;
  final Directory? recordings;
  final Alerts? alerts;
  final Speech? speech;

  /// The hike was just shared with contacts (see [LiveShare]).
  final LiveShare? live;

  /// For tests: stands in for the Apple Watch.
  final WatchLink? watch;

  @override
  State<NavigateScreen> createState() => _NavigateScreenState();
}

class _NavigateScreenState extends State<NavigateScreen> {
  late final RouteTracker _tracker = RouteTracker(
    widget.route.line,
    durationS: widget.route.totals.durationS,
    ascentM: widget.route.totals.ascentM,
  );
  late final Alerts _alerts = widget.alerts ?? Alerts();
  late final Speech _speech = widget.speech ?? Speech();
  late TurnGuide? _guide = widget.turns == null ? null : TurnGuide(widget.turns!);
  late final WatchLink _watch = widget.watch ?? WatchLink.instance;
  late final _watchLine = simplifyLine(widget.route.line, WatchLink.maxPoints);
  late final _controls = HikeControls(pause: _pause, resume: _resume, stop: () => _finish(ask: false));
  bool _voice = true;
  Recording? _recording;
  LiveSender? _live;
  StreamSubscription<Fix>? _sub;
  MapController? _map;
  StyleController? _style;
  Progress? _progress;
  Fix? _fix;
  bool _follow = true;
  bool _denied = false;

  /// The GPS reported a problem (e.g. location switched off) since the last
  /// position.
  GpsProblem? _gps;
  bool _saveWarned = false; // said once that fixes cannot be saved

  /// The off-route warning is out (not while paused).
  bool _warnedOff = false;

  /// «Beenden?» is being asked.
  bool _asking = false;

  /// While following the position; panning or zooming stops following.
  static const _followZoom = 15.0;
  Timer? _clock;
  late final _places = PlaceLayer(widget.api, onTap: (p) => showPlace(context, p));

  /// Built once: every position rebuilds the screen, and neither the map
  /// nor the route's profile change with it.
  late final Widget _mapView = LayoutBuilder(
    builder: (context, size) {
      final view = fitLine(widget.route.line, size.maxWidth, size.maxHeight);
      final pack = widget.pack;
      return MapLibreMap(
        options: MapOptions(
          initStyle: pack != null ? offlineStyle(pack.files) : swisstopoStyle(widget.api.server),
          initCenter: Geographic(lon: view.lon, lat: view.lat),
          initZoom: view.zoom,
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
    },
  );
  late final _profileM = cumulativeM(widget.route.line);
  late final _profileEle = [for (final p in widget.route.line) p.length > 2 ? p[2] : 0.0];

  @override
  void initState() {
    super.initState();
    Analytics.instance.screen('navigate');
    NavigateScreen.running = true;
    _tracker.speedFactor = hikerPace.value; // as last known, also offline
    widget.api
        .me()
        .then((m) {
          if (mounted) setState(() => _tracker.speedFactor = m.speedFactor);
        })
        .catchError((_) {}); // offline: the signposts' pace
    if (_guide == null) {
      widget.api
          .turns(widget.route.id)
          .then((turns) {
            if (mounted) setState(() => _guide = TurnGuide(turns));
          })
          .catchError((_) {}); // offline and not saved with the map: no turns
    }
    _start();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {})); // elapsed time
  }

  Future<void> _start() async {
    // Asked first: without the location, nothing is recorded.
    if (widget.positions == null && !await locationAllowed()) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    final root = widget.recordings ?? await Recording.defaultRoot();
    var rec = await Recording.active(root);
    if (Recording.before(rec, widget.route.id, widget.api.userId) case Before.ask || Before.setAside) {
      // Another route's hike (the route screen asked) or another account's:
      // kept for uploading, and this one starts.
      await rec!.finish();
      rec = null;
    }
    rec ??= await Recording.start(root, routeId: widget.route.id, title: widget.route.title, owner: widget.api.userId);
    if (widget.live case final live?) await rec.setLive(live.id, live.expectedEnd);
    if (rec.liveId case final id?) _live = LiveSender(widget.api, id);
    // Resumed: continue where the hike was.
    for (final f in await rec.fixes()) {
      _progress = _tracker.update(f) ?? _progress;
    }
    if (!mounted) return;
    setState(() => _recording = rec);
    _watch.controls = _controls;
    _toWatch();
    _sub = (widget.positions ?? () => gpsFixes(AppLocalizations.of(context)))().listen(
      _onFix,
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _gps = gpsProblem(e));
        _toWatch();
      },
    );
    unawaited(_alerts.init()); // asks for notifications without holding up the GPS
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

  bool get _paused => _recording?.pausedAt != null;

  Future<void> _pause() async {
    await _recording?.pause().catchError((Object _) => _saveFailed());
    if (!mounted) return;
    setState(() {});
    _toWatch();
  }

  Future<void> _resume() async {
    await _recording?.resume().catchError((Object _) => _saveFailed());
    if (!mounted) return;
    setState(() {});
    _toWatch();
  }

  /// What the watch shows: after every position and change.
  void _toWatch() {
    final rec = _recording;
    if (rec == null) return;
    final p = _progress;
    unawaited(
      _watch.show(
        WatchHike(
          title: widget.route.title,
          routeId: widget.route.id,
          paused: rec.pausedAt != null,
          elapsed: rec.elapsed(DateTime.now()),
          line: _watchLine,
          position: _fix,
          progress: p,
          turn: switch (p == null ? null : _guide?.next(p.doneM)) {
            (final turn, final inM)? => (turn.kind, inM),
            null => null,
          },
          gps: _gps,
        ),
      ),
    );
  }

  Future<void> _onFix(Fix fix) async {
    // Paused: the position shows, but is not recorded.
    if (!_paused) {
      try {
        await _recording?.add(fix);
      } on Object {
        _saveFailed();
      }
    }
    unawaited(_live?.add(fix)); // contacts see where one is, also during a pause
    final p = _tracker.update(fix);
    if (!mounted) return;
    setState(() {
      _fix = fix;
      _progress = p ?? _progress;
      _gps = null;
    });
    _toWatch();
    await _style?.updateGeoJsonSource(id: 'me', data: positionJson(fix.lon, fix.lat));
    if (_follow) {
      // A short glide rather than a jump to each position.
      // The next position or a gesture can cut it short (Android then fails it).
      await _map
          ?.animateCamera(
            center: Geographic(lon: fix.lon, lat: fix.lat),
            zoom: _followZoom,
            nativeDuration: const Duration(milliseconds: 400),
          )
          .catchError((_) {});
    }
    if (p == null || !mounted) return;
    final t = AppLocalizations.of(context);
    // Nothing said or warned during a pause (the way to the restaurant).
    if (_guide?.prompt(p) case final prompt? when _voice && !_paused) {
      await _speech.say(_promptText(t, prompt), Localizations.localeOf(context).languageCode);
    }
    final off = p.offRoute && !_paused;
    if (off == _warnedOff || !mounted) return;
    _warnedOff = off;
    if (off) {
      await HapticFeedback.vibrate();
      await _alerts.offRoute(t.navOffRouteTitle, t.navOffRoute(p.distanceToRouteM.round()));
    } else {
      await _alerts.clear();
    }
  }

  Future<void> _onStyle(StyleController style) async {
    await _places.addTo(style);
    await addRouteLine(style, widget.route.line);
    await addPositionDot(style, _fix?.lon, _fix?.lat);
    // Only now: a position coming in meanwhile would update the dot's
    // source before it exists (the iOS plugin fails on that).
    _style = style;
  }

  /// Ends the hike; [ask] first, unless the watch asked already.
  Future<void> _finish({bool ask = true}) async {
    if (_asking) {
      // Asked on the phone and stopped on the watch: as «Beenden».
      if (!ask) Navigator.of(context).pop(true);
      return;
    }
    if (ask) {
      final t = AppLocalizations.of(context);
      _asking = true;
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
      _asking = false;
      if (ok != true || !mounted) return;
    }
    _endWatch();
    await _sub?.cancel();
    _sub = null;
    await _alerts.clear();
    final rec = _recording;
    HikeSummary? summary;
    if (rec?.liveId case final id?) {
      // The contacts must not be alerted about a hike that ended.
      await LiveOutbox(rec!.root).end(widget.api, id);
    }
    if (rec != null) {
      final fixes = await rec.fixes();
      await rec.finish();
      summary = HikeSummary(
        trackLengthM(fixes),
        fixes.isEmpty ? Duration.zero : rec.elapsed(fixes.last.time),
        rec.started.toIso8601String(),
      );
    }
    if (mounted) Navigator.of(context).pop(summary);
  }

  /// «Später»: the expected end one hour on.
  Future<void> _later() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final rec = _recording;
    final id = rec?.liveId;
    if (rec == null || id == null) return;
    final base = rec.expectedEnd != null && rec.expectedEnd!.isAfter(DateTime.now())
        ? rec.expectedEnd!
        : DateTime.now();
    final end = base.add(const Duration(hours: 1));
    try {
      await widget.api.extendLive(id, end);
      await rec.setLive(id, end);
      if (mounted) setState(() {});
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.liveLaterFailed)));
    }
  }

  /// The watch no longer shows this hike.
  void _endWatch() {
    if (!identical(_watch.controls, _controls)) return;
    _watch.controls = null;
    unawaited(_watch.show(null));
  }

  @override
  void dispose() {
    NavigateScreen.running = false;
    _endWatch();
    _sub?.cancel();
    _clock?.cancel();
    _places.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final r = widget.route;
    final p = _progress;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(r.title),
          actions: [
            if (_recording != null)
              IconButton(
                key: const Key('nav-pause'),
                onPressed: _paused ? _resume : _pause,
                icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                tooltip: _paused ? t.navUnpause : t.navPause,
              ),
            IconButton(
              key: const Key('nav-voice'),
              onPressed: () => setState(() => _voice = !_voice),
              icon: Icon(_voice ? Icons.volume_up : Icons.volume_off),
              tooltip: _voice ? t.navVoiceOff : t.navVoiceOn,
            ),
            TextButton(key: const Key('nav-finish'), onPressed: _finish, child: Text(t.navFinish)),
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
            if (_recording?.expectedEnd case final end? when _recording?.liveId != null)
              Material(
                key: const Key('nav-live'),
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.share_location, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(t.liveSharedUntil(formatTime(end)), style: Theme.of(context).textTheme.bodySmall),
                      ),
                      TextButton(key: const Key('nav-live-later'), onPressed: _later, child: Text(t.liveLater)),
                    ],
                  ),
                ),
              ),
            if (_gps case final problem?)
              _Banner(
                key: const Key('nav-gps-lost'),
                color: Theme.of(context).colorScheme.errorContainer,
                text: gpsText(t, problem),
              )
            else if (_paused)
              _Banner(
                key: const Key('nav-paused'),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                icon: Icons.pause,
                text: t.navPaused,
              )
            else if (p != null && p.offRoute)
              _Banner(
                key: const Key('nav-off-route'),
                color: Theme.of(context).colorScheme.errorContainer,
                text: t.navOffRoute(p.distanceToRouteM.round()),
              )
            else if (p != null && p.arrived)
              _Banner(color: Theme.of(context).colorScheme.primaryContainer, text: t.navArrived)
            else if (p != null)
              if (_guide?.next(p.doneM) case (final turn, final inM)?)
                _Banner(
                  key: const Key('nav-turn'),
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  icon: _turnIcons[turn.kind],
                  text: '${turnText(t, turn.kind)} · ${formatDistance(inM)}',
                ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: _denied
                    ? Text(t.navNoPermission)
                    : p == null
                    ? Text(t.navWaiting)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ElevationProfile(distances: _profileM, elevations: _profileEle, markerM: p.doneM, height: 80),
                          const SizedBox(height: 4),
                          Row(
                            key: const Key('nav-progress'),
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            spacing: 8,
                            children: [
                              _Stat(t.navDone, '${formatDistance(p.doneM)} · ↑\u00a0${formatHeight(p.ascentDoneM)}'),
                              _Stat(
                                t.navRemaining,
                                '${formatDistance(p.remainingM)} · ${formatDuration(p.remaining.inSeconds)}\n'
                                '↑\u00a0${formatHeight(p.ascentRemainingM)}',
                              ),
                              if (_recording != null)
                                _Stat(t.navElapsed, formatDuration(_recording!.elapsed(DateTime.now()).inSeconds)),
                            ],
                          ),
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
    // Flexible: with large text the three wrap instead of running off.
    return Flexible(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.labelMedium),
          Text(value, style: theme.titleMedium),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.color, required this.text, this.icon});
  final Color color;
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: color,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        if (icon != null) ...[Icon(icon), const SizedBox(width: 8)],
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleSmall)),
      ],
    ),
  );
}

/// What a prompt says.
String _promptText(AppLocalizations t, Prompt p) => switch (p) {
  Prompt(turn: null) => t.navArrived,
  Prompt(turn: final turn?, inM: final metres?) => t.turnIn(metres, _lowerFirst(turnText(t, turn.kind))),
  Prompt(turn: final turn?) => turnText(t, turn.kind),
};

String _lowerFirst(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

/// The text of a turn kind (see Turn).
String turnText(AppLocalizations t, String kind) => switch (kind) {
  'sharp_left' => t.turnSharpLeft,
  'left' => t.turnLeft,
  'slight_left' => t.turnSlightLeft,
  'keep_left' => t.turnKeepLeft,
  'u_turn' => t.turnUTurn,
  'slight_right' => t.turnSlightRight,
  'right' => t.turnRight,
  'sharp_right' => t.turnSharpRight,
  'keep_right' => t.turnKeepRight,
  _ => kind,
};

const _turnIcons = {
  'sharp_left': Icons.turn_sharp_left,
  'left': Icons.turn_left,
  'slight_left': Icons.turn_slight_left,
  'keep_left': Icons.fork_left,
  'u_turn': Icons.u_turn_left,
  'slight_right': Icons.turn_slight_right,
  'right': Icons.turn_right,
  'sharp_right': Icons.turn_sharp_right,
  'keep_right': Icons.fork_right,
};

/// What the banner says when fixes stopped coming.
String gpsText(AppLocalizations t, GpsProblem problem) => switch (problem) {
  GpsProblem.lost => t.navWaiting,
  GpsProblem.denied => t.navNoPermission,
  GpsProblem.off => t.gpsOff,
};
