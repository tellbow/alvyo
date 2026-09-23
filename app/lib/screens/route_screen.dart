import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import '../api.dart';
import '../camera.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../map_style.dart';
import '../navigation/recording.dart';
import '../navigation/uploads.dart';
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
  ({bool downloading, double share})? _progress; // while saving

  @override
  void initState() {
    super.initState();
    Recording.defaultRoot().then(Recording.active).then((rec) {
      if (mounted && rec?.routeId == widget.id) setState(() => _resumable = true);
    });
  }

  Future<void> _hike(RouteDetail r) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final summary = await Navigator.of(context).push<HikeSummary>(
      MaterialPageRoute(
        builder: (_) => NavigateScreen(api: widget.api, route: r, pack: _pack),
      ),
    );
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
      ),
    );
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

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _progress = (downloading: false, share: 0));
    try {
      final pack = await (await _store).save(
        widget.api,
        widget.id,
        progress: (downloading, share) {
          if (mounted) setState(() => _progress = (downloading: downloading, share: share));
        },
        cancelled: () => !mounted,
      );
      if (mounted) {
        setState(() {
          _pack = pack;
          _outdated = false;
          _route = Future.value(pack.route);
        });
      }
    } on SaveCancelled {
      // left the screen
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(t.offlineFailed)));
    } finally {
      if (mounted) setState(() => _progress = null);
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
                      FilledButton.icon(
                        key: const Key('nav-start'),
                        onPressed: _progress == null ? () => _hike(r) : null,
                        icon: const Icon(Icons.hiking),
                        label: Text(_resumable ? t.navResume : t.navStart),
                      ),
                      const SizedBox(height: 8),
                      if (_progress case final p?) ...[
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
              ),
            ],
          );
        },
      ),
    );
  }
}
