import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import '../api.dart';
import '../camera.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../map_style.dart';
import '../navigation/recording.dart';
import '../navigation/uploads.dart';
import '../offline/downloads.dart';
import '../offline/packs.dart';
import '../route_layers.dart';
import 'navigate_screen.dart';

/// A route on the national map, with offline saving.
class RouteScreen extends StatefulWidget {
  const RouteScreen({super.key, required this.api, required this.id, required this.title});
  final Api api;
  final String id;
  final String title;

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  final Future<PackStore> _store = PackStore.open();
  late Future<RouteDetail> _route = _load();
  SavedPack? _pack;
  bool _outdated = false;
  bool _resumable = false; // a hike on this route is still being recorded
  bool _hiking = false;
  final _downloads = PackDownloads.instance;

  @override
  void initState() {
    super.initState();
    Recording.defaultRoot().then(Recording.active).then((rec) {
      final resume = Recording.before(rec, widget.id, widget.api.userId) == Before.resume;
      if (mounted && resume) setState(() => _resumable = true);
    });
    // Saving since the screen was open before.
    _downloads.running(widget.id)?.then(_saved).catchError((_) {});
  }

  void _saved(SavedPack pack) {
    if (!mounted) return;
    setState(() {
      _pack = pack;
      _outdated = false;
      _route = Future.value(pack.route);
    });
  }

  Future<void> _hike(RouteDetail r) async {
    if (_hiking) return; // a double tap would record twice
    _hiking = true;
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final active = await Recording.active(await Recording.defaultRoot());
    if (!mounted) return;
    if (Recording.before(active, r.id, widget.api.userId) == Before.ask) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(t.navSwitchQuestion(active!.title)),
          actions: [
            TextButton(
              key: const Key('nav-switch-cancel'),
              onPressed: () => Navigator.pop(context, false),
              child: Text(t.cancel),
            ),
            FilledButton(
              key: const Key('nav-switch-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(t.navSwitch),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) {
        _hiking = false;
        return;
      }
    }
    final summary = await Navigator.of(context).push<HikeSummary>(
      MaterialPageRoute(
        builder: (_) => NavigateScreen(api: widget.api, route: r, pack: _pack, turns: _pack?.turns),
      ),
    );
    _hiking = false;
    if (!mounted) return;
    setState(() => _resumable = false);
    if (summary == null) return;
    final uploaded = await uploadHikes(widget.api, await Recording.defaultRoot()).catchError((_) => 0);
    final distance = formatDistance(summary.distanceM), duration = formatDuration(summary.duration.inSeconds);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          key: const Key('nav-saved'),
          uploaded > 0 ? t.navUploaded(distance, duration) : t.navSaved(distance, duration),
        ),
        duration: const Duration(seconds: 8),
        // A stage's route: offer to tick the stage off.
        action: r.journeyId == null
            ? null
            : SnackBarAction(
                key: const Key('nav-stage-done'),
                label: t.navMarkStageDone,
                onPressed: () => _stageDone(r),
              ),
      ),
    );
  }

  /// Marks the stage whose route [r] is as hiked today.
  Future<void> _stageDone(RouteDetail r) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final j = await widget.api.journey(r.journeyId!);
      final stage = j.stages.firstWhere((s) => s.routeId == r.id);
      if (stage.status != 'done') await widget.api.setStageDone(j.id, stage, true);
      messenger.showSnackBar(SnackBar(content: Text(key: const Key('nav-stage-marked'), t.stageMarkedDone)));
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    }
  }

  /// The saved copy if there is one, so it opens offline; else the server's.
  Future<RouteDetail> _load() async {
    final pack = await (await _store).saved(widget.id);
    if (pack == null) return widget.api.route(widget.id);
    _pack = pack;
    widget.api
        .packStatus(widget.id)
        .then((st) {
          if (mounted && st.key != pack.key) setState(() => _outdated = true);
        })
        .catchError((_) {}); // offline: keep what is saved
    return pack.route;
  }

  /// Goes on when the screen is left; see PackDownloads.
  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      _saved(await _downloads.save(widget.api, widget.id));
    } catch (_) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(t.offlineFailed)));
    }
  }

  Future<void> _remove() async {
    await (await _store).delete(widget.id);
    if (mounted) {
      setState(() {
        _pack = null;
        _outdated = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder(
        future: _route,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(t.errorServer));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final r = snap.data!;
          final pack = _pack;
          return Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, size) {
                    final view = fitLine(r.line, size.maxWidth, size.maxHeight);
                    return MapLibreMap(
                      key: ValueKey(pack?.key), // a new style needs a new map
                      options: MapOptions(
                        initStyle: pack != null ? offlineStyle(pack.files) : swisstopoStyle(widget.api.server),
                        initCenter: Geographic(lon: view.lon, lat: view.lat),
                        initZoom: view.zoom,
                      ),
                      onStyleLoaded: (style) => addRouteLine(style, r.line),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${formatDistance(r.totals.distanceM)} · ${formatDuration(r.totals.durationS)} · '
                        '↑ ${r.totals.ascentM.round()} m ↓ ${r.totals.descentM.round()} m · '
                        '${formatSac(r.totals.sacGrade, r.totals.sacMax)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ValueListenableBuilder(
                        valueListenable: _downloads.progress(widget.id),
                        builder: (context, progress, _) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton.icon(
                              key: const Key('nav-start'),
                              onPressed: progress == null ? () => _hike(r) : null,
                              icon: const Icon(Icons.hiking),
                              label: Text(_resumable ? t.navResume : t.navStart),
                            ),
                            const SizedBox(height: 8),
                            if (progress case final p?) ...[
                              Text(p.downloading ? t.offlineDownloading : t.offlinePreparing),
                              const SizedBox(height: 4),
                              LinearProgressIndicator(value: p.share),
                            ] else if (pack != null) ...[
                              if (_outdated)
                                FilledButton.icon(
                                  key: const Key('offline-update'),
                                  onPressed: _save,
                                  icon: const Icon(Icons.sync),
                                  label: Text(t.offlineOutdated),
                                ),
                              OutlinedButton.icon(
                                key: const Key('offline-remove'),
                                onPressed: _remove,
                                icon: const Icon(Icons.offline_pin),
                                label: Text(t.offlineSaved),
                              ),
                            ] else
                              FilledButton.tonalIcon(
                                key: const Key('offline-save'),
                                onPressed: _save,
                                icon: const Icon(Icons.download),
                                label: Text(t.offlineSave),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
