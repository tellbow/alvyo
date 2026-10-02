import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import '../api.dart';
import '../bug_report.dart';
import '../camera.dart';
import '../elevation_profile.dart';
import '../pois.dart';
import '../protected_areas.dart';
import '../weather.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../map_style.dart';
import '../navigation/recording.dart';
import '../navigation/uploads.dart';
import '../offline/downloads.dart';
import '../offline/packs.dart';
import '../place_layer.dart';
import '../route_layers.dart';
import '../travel.dart';
import 'collections_screen.dart';
import 'details.dart';
import 'item_menu.dart';
import 'live_sheet.dart';
import 'navigate_screen.dart';
import 'photos.dart';
import 'report_dialog.dart';
import 'social.dart';
import 'tag_chips.dart';
import 'planner_screen.dart';
import 'travel_screen.dart';

/// A route on the national map, with offline saving; its description,
/// photos and comments, and a menu to change, share or export it.
class RouteScreen extends StatefulWidget {
  const RouteScreen({super.key, required this.api, required this.id, required this.title, this.map});
  final Api api;
  final String id;
  final String title;

  /// Stands in for the map in widget tests.
  @visibleForTesting
  final Widget? map;

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> with ReportsPlace<RouteScreen> {
  @override
  String get place => '/routes/${widget.id}';

  final Future<PackStore> _store = PackStore.open();
  late Future<RouteDetail> _route = _load();
  late final Future<Along> _areas = widget.api
      .areas(routeId: widget.id)
      .catchError((_) => (areas: <ProtectedArea>[], notices: <Notice>[]));
  late final Future<List<Poi>> _pois = widget.api.pois(widget.id).catchError((_) => <Poi>[]);
  int _poiCount = 0;
  _Tab _tab = _Tab.overview;
  late final Future<RouteWeather?> _weather = widget.api
      .routeWeather(widget.id)
      .then<RouteWeather?>((w) => w, onError: (_) => null);
  SavedPack? _pack;
  bool _outdated = false;
  bool _resumable = false; // a hike on this route is still being recorded
  bool _hiking = false;
  final _downloads = PackDownloads.instance;
  late final _places = PlaceLayer(widget.api, onTap: (p) => showPlace(context, p));

  @override
  void initState() {
    super.initState();
    Recording.defaultRoot().then(Recording.active).then((rec) {
      final resume = Recording.before(rec, widget.id, widget.api.userId) == Before.resume;
      if (mounted && resume) setState(() => _resumable = true);
    });
    // Saving since the screen was open before.
    _downloads.running(widget.id)?.then(_saved).catchError((_) {});
    _pois.then((p) {
      if (mounted) setState(() => _poiCount = p.length);
    });
  }

  @override
  void dispose() {
    _places.dispose();
    super.dispose();
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
    // A new hike (not one resumed) can be shared with contacts.
    LiveShare? live;
    if (Recording.before(active, r.id, widget.api.userId) != Before.resume) {
      final root = await Recording.defaultRoot();
      if (!mounted) {
        _hiking = false;
        return;
      }
      live = await askToShare(context, api: widget.api, route: r, recordings: root);
      if (!mounted) {
        _hiking = false;
        return;
      }
    }
    final summary = await Navigator.of(context).push<HikeSummary>(
      MaterialPageRoute(
        builder: (_) => NavigateScreen(api: widget.api, route: r, pack: _pack, turns: _pack?.turns, live: live),
      ),
    );
    _hiking = false;
    if (!mounted) return;
    setState(() => _resumable = false);
    if (summary == null) return;
    final routes = await uploadHikes(widget.api, await Recording.defaultRoot()).catchError((_) => <String, String?>{});
    messenger.showSnackBar(
      SnackBar(
        content: Text(key: const Key('nav-saved'), summary.message(t, routes)),
        duration: const Duration(seconds: 8),
        // A stage's route: offer to tick the stage off, if the user may.
        action: r.journeyId == null || !r.canEdit
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

  /// Title, description, tags and visibility; a stage route's tags are its
  /// journey's, and only the owner changes who sees it.
  Future<void> _edit(RouteDetail r) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final stage = r.journeyId != null;
    final now = Details(title: r.title, description: r.description, tags: r.tags, visibility: r.visibility);
    final next = await editDetails(context, now, tags: !stage, visibility: r.isOwner && !stage);
    if (next == null) return;
    final changes = detailChanges(now, next, tags: !stage);
    if (changes.isEmpty) return;
    try {
      final updated = await widget.api.updateRoute(r.id, r.version, changes);
      if (mounted) {
        setState(() {
          _route = Future.value(updated);
        });
      }
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(changeError(t, e))));
      if (e is ApiException && e.status == 412 && mounted) {
        setState(() {
          _route = widget.api.route(widget.id);
        });
      }
    }
  }

  /// A new start, destination or points between, in the planner; the
  /// route opens anew once saved.
  Future<void> _editLine(RouteDetail r) async {
    final nav = Navigator.of(context);
    final saved = await nav.push<Object>(
      MaterialPageRoute(
        builder: (_) => PlannerScreen(api: widget.api, edit: r),
      ),
    );
    if (saved is! RouteDetail || !mounted) return;
    nav.pushReplacement(
      MaterialPageRoute(
        builder: (_) => RouteScreen(api: widget.api, id: saved.id, title: saved.title),
      ),
    );
  }

  /// Deletes the route on the server and its offline map, then leaves.
  Future<void> _delete() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await widget.api.deleteRoute(widget.id);
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
      return;
    }
    await (await _store).delete(widget.id);
    if (mounted) nav.pop();
  }

  /// A stage's route is shared, collected and deleted with its journey.
  Widget _menu(AppLocalizations t, RouteDetail r) {
    final stage = r.journeyId != null;
    return ItemMenu(
      actions: [
        if (r.canEdit) MenuAction('edit', Icons.edit_outlined, t.editAction, () => _edit(r)),
        if (r.canEdit && r.anchors.length > 1)
          MenuAction('edit-line', Icons.alt_route, t.routeEditLine, () => _editLine(r)),
        if (r.isOwner && !stage)
          MenuAction(
            'share',
            Icons.share_outlined,
            t.shareAction,
            () => shareSheet(
              context,
              widget.api,
              id: r.id,
              journey: false,
              visibility: r.visibility,
              token: r.shareToken,
            ),
          ),
        MenuAction('gpx', Icons.file_download_outlined, t.gpxRoute, () => shareGpx(context, widget.api, r.id, r.title)),
        if (!stage)
          MenuAction(
            'collection',
            Icons.collections_bookmark_outlined,
            t.collectionAddTo,
            () => addToCollection(context, widget.api, r.id, journey: false),
          ),
        if (!r.isOwner)
          MenuAction(
            'report',
            Icons.flag_outlined,
            t.reportAction,
            () => report(context, widget.api, kind: 'route', id: r.id),
          ),
      ],
      question: t.routeDeleteConfirm,
      onDelete: r.isOwner && !stage ? _delete : null,
    );
  }

  /// The four numbers, who planned it, and starting the hike.
  Widget _head(AppLocalizations t, RouteDetail r, SavedPack? pack) {
    final theme = Theme.of(context);
    // Four in a row on the narrowest phone: what does not fit shrinks.
    Widget stat(String label, Widget value) => Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(fit: BoxFit.scaleDown, child: value),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
    final strong = theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const Key('route-stats'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            spacing: 4,
            children: [
              stat(t.statTime, Text(formatHikingTime(r.totals.durationS), style: strong)),
              stat(t.statDistance, Text(formatDistance(r.totals.distanceM), style: strong)),
              stat(t.statHeights, Text('↑${r.totals.ascentM.round()} ↓${r.totals.descentM.round()}', style: strong)),
              stat(t.statSac, Text(formatSac(r.totals.sacGrade, r.totals.sacMax), style: strong)),
            ],
          ),
        ),
        if (!r.isOwner) OwnerLine(api: widget.api, owner: r.owner, open: true),
        if (r.tags.isNotEmpty) ...[const SizedBox(height: 4), TagChips(r.tags)],
        if (r.hikedAt != null) ...[
          const SizedBox(height: 4),
          Text(
            key: const Key('hike-privacy'),
            r.canEdit
                ? t.routePrivacyOwner
                : r.line.length < 2
                ? t.routePrivacyAll
                : t.routePrivacyOthers,
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (r.line.length >= 2) ...[
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
                  // Below «Wanderung starten», not as bright.
                  OutlinedButton.icon(
                    key: const Key('offline-save'),
                    onPressed: _save,
                    icon: const Icon(Icons.download),
                    label: Text(t.offlineSave),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _tabBar(AppLocalizations t, List<_Tab> tabs) {
    final theme = Theme.of(context);
    String label(_Tab tab) => switch (tab) {
      _Tab.overview => t.routeTabOverview,
      _Tab.along => '${t.poisTitle} $_poiCount',
      _Tab.travel => t.routeTabTravel,
      _Tab.photos => t.photosTitle,
    };
    return Material(
      color: theme.colorScheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              for (final tab in tabs)
                InkWell(
                  key: Key('tab-${tab.name}'),
                  onTap: () => setState(() => _tab = tab),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: tab == _tab ? theme.colorScheme.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      label(tab),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: tab == _tab ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                        fontWeight: tab == _tab ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// A tab's content, kept (with what it loaded) while another is shown.
  Widget _pane(_Tab tab, Widget child) => Visibility(visible: _tab == tab, maintainState: true, child: child);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      // No field here: a keyboard still closing (the title dialog before)
      // takes no room from the map and the panel.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: FutureBuilder(future: _route, builder: (context, snap) => Text(snap.data?.title ?? widget.title)),
        actions: [
          FutureBuilder(
            future: _route,
            builder: (context, snap) => switch (snap.data) {
              final r? => _menu(t, r),
              _ => const SizedBox.shrink(),
            },
          ),
        ],
      ),
      body: FutureBuilder(
        future: _route,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(t.errorServer));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final r = snap.data!;
          final pack = _pack;
          final tabs = [
            _Tab.overview,
            if (_poiCount > 0) _Tab.along,
            // A stage's way there and back is its journey's; its photos and
            // comments are on its journey too.
            if (r.line.length >= 2 && r.journeyId == null) _Tab.travel,
            if (r.journeyId == null) _Tab.photos,
          ];
          return LayoutBuilder(
            builder: (context, body) => Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      widget.map ??
                          LayoutBuilder(
                            builder: (context, size) {
                              // Someone else's short hike: no line, Switzerland.
                              final view = r.line.isEmpty
                                  ? (lon: 8.23, lat: 46.8, zoom: 7.0)
                                  : fitLine(r.line, size.maxWidth, size.maxHeight);
                              return MapLibreMap(
                                key: ValueKey(pack?.key), // a new style needs a new map
                                options: MapOptions(
                                  initStyle: pack != null
                                      ? offlineStyle(pack.files)
                                      : swisstopoStyle(widget.api.server),
                                  initCenter: Geographic(lon: view.lon, lat: view.lat),
                                  initZoom: view.zoom,
                                ),
                                onEvent: _places.onEvent,
                                onStyleLoaded: (style) async {
                                  await _places.addTo(style);
                                  await addRouteLine(style, r.line);
                                  await _places.addAlong(style, await _pois);
                                },
                              );
                            },
                          ),
                      const Positioned(top: 12, right: 12, child: PlaceLayerButton()),
                    ],
                  ),
                ),
                // Half the screen, so it keeps its height between the tabs; the
                // tab bar stays while the rest scrolls.
                SizedBox(
                  height: body.maxHeight / 2,
                  child: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        sliver: SliverToBoxAdapter(child: _head(t, r, pack)),
                      ),
                      if (tabs.length > 1) SliverPersistentHeader(pinned: true, delegate: _TabBar(_tabBar(t, tabs))),
                      SliverSafeArea(
                        top: false,
                        sliver: SliverPadding(
                          padding: const EdgeInsets.all(12),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Every tab stays built: the map shows what each one loads.
                                _pane(
                                  _Tab.overview,
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      if (r.description.isNotEmpty) ...[
                                        Text(key: const Key('route-description'), r.description),
                                        const SizedBox(height: 8),
                                      ],
                                      ElevationProfile.ofLine(r.line),
                                      ProtectedAreas(_areas),
                                      RouteWeatherView(
                                        _weather,
                                        later: (date) => widget.api
                                            .routeWeather(widget.id, date: date)
                                            .then<RouteWeather?>((w) => w, onError: (_) => null),
                                      ),
                                    ],
                                  ),
                                ),
                                _pane(_Tab.along, PoiList(_pois)),
                                if (tabs.contains(_Tab.travel))
                                  _pane(
                                    _Tab.travel,
                                    TravelTiles(
                                      api: widget.api,
                                      ends: routeEnds(r, start: t.travelRouteStart, end: t.travelRouteEnd),
                                      load: () => widget.api.routeTravel(widget.id),
                                      save: (travel) => widget.api.setRouteTravel(widget.id, travel),
                                      pickDay: true,
                                    ),
                                  ),
                                if (tabs.contains(_Tab.photos))
                                  _pane(
                                    _Tab.photos,
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        PhotoStrip(api: widget.api, id: r.id),
                                        SocialPanel(api: widget.api, id: r.id),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

enum _Tab { overview, along, travel, photos }

/// The tab bar, pinned to the top of the panel while it scrolls.
class _TabBar extends SliverPersistentHeaderDelegate {
  _TabBar(this.child);
  final Widget child;

  @override
  double get minExtent => 46;

  @override
  double get maxExtent => 46;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => SizedBox.expand(child: child);

  @override
  bool shouldRebuild(_TabBar old) => true;
}
