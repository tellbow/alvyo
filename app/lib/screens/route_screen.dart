import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import 'error_state.dart';
import '../analytics.dart';
import '../api.dart';
import '../breakdown.dart';
import '../bug_report.dart';
import '../camera.dart';
import '../elevation_profile.dart';
import '../pois.dart';
import '../protected_areas.dart';
import '../weather.dart';
import '../l10n/app_localizations.dart';
import '../map_credit.dart';
import '../map_style.dart';
import '../my_location.dart';
import '../navigation/recording.dart';
import '../navigation/uploads.dart';
import '../offline/downloads.dart';
import '../offline/packs.dart';
import '../place_layer.dart';
import '../route_layers.dart';
import '../travel.dart';
import 'collections_screen.dart';
import 'details.dart';
import 'done.dart';
import 'item_menu.dart';
import 'live_sheet.dart';
import 'panel_tabs.dart';
import 'tour_card.dart';
import 'navigate_screen.dart';
import 'photos.dart';
import 'report_dialog.dart';
import 'social.dart';
import 'tag_chips.dart';
import 'planner_screen.dart';
import 'travel_screen.dart';
import 'wide.dart';

/// A route on the national map, with offline saving; its description,
/// photos and comments, and a menu to change, share or export it.
class RouteScreen extends StatefulWidget {
  const RouteScreen({
    super.key,
    required this.api,
    required this.id,
    required this.title,
    this.map,
    this.startHike = false,
    this.fromWatch = false,
    this.image,
  });
  final Api api;
  final String id;
  final String title;

  /// Its card's map ([Api.routeImageUrl]): flies in from the card and
  /// stands in for the map until the map shows the line.
  final String? image;

  /// Starts following the route once loaded, as «Los» does (a tour chosen
  /// on Aufzeichnen).
  final bool startHike;

  /// Started on the watch: nobody looks at the phone to answer its
  /// questions, so another hike in progress is ended (kept for uploading)
  /// and the hike is not shared.
  final bool fromWatch;

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
  late final Future<Steepness?> _steep = widget.api
      .steepness(widget.id)
      .then<Steepness?>((s) => s, onError: (_) => null);
  late final Future<SnowAlong?> _snow = widget.api
      .snowAlong(routeId: widget.id)
      .then<SnowAlong?>((s) => s, onError: (_) => null);
  MapController? _map;
  StyleController? _style;
  bool _lineShown = false;
  late final Future<List<Poi>> _pois = widget.api.pois(widget.id).catchError((_) => <Poi>[]);
  int _poiCount = 0;
  _Tab _tab = _Tab.overview;

  /// When the user hiked it, as changed here; else as loaded.
  DoneState? _done;

  /// How many photos there are, once loaded (the «Fotos» tab says so).
  int? _photoCount;

  /// How many comments there are, once loaded («Kommentare» and the count above).
  int? _commentCount;
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
    Analytics.instance.screen('route');
    Recording.defaultRoot().then(Recording.active).then((rec) {
      final resume = Recording.before(rec, widget.id, widget.api.userId) == Before.resume;
      if (mounted && resume) setState(() => _resumable = true);
    });
    // Saving since the screen was open before.
    _downloads.running(widget.id)?.then(_saved).catchError((_) {});
    _pois.then((p) {
      if (mounted) setState(() => _poiCount = p.length);
    });
    if (widget.startHike) {
      _route.then((r) {
        if (mounted) _hike(r);
      }, onError: (Object _) {});
    }
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
    if (NavigateScreen.running) {
      // Opened from a link during a hike: back to it, not a second one
      // writing into the same recording.
      Navigator.of(context).popUntil(ModalRoute.withName(NavigateScreen.routeName));
      return;
    }
    _hiking = true;
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final active = await Recording.active(await Recording.defaultRoot());
    if (!mounted) return;
    if (Recording.before(active, r.id, widget.api.userId) == Before.ask && !widget.fromWatch) {
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
    if (Recording.before(active, r.id, widget.api.userId) != Before.resume && !widget.fromWatch) {
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
        settings: const RouteSettings(name: NavigateScreen.routeName),
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

  /// «Als eigene Route bearbeiten»: the user's private copy, opened in the
  /// planner; afterwards the copy's page takes this one's place.
  Future<void> _copy(RouteDetail r) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final RouteDetail copy;
    try {
      copy = await widget.api.copyRoute(r.id);
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.copyFailed)));
      return;
    }
    if (!mounted) return;
    final saved = await nav.push<Object>(
      MaterialPageRoute(
        builder: (_) => PlannerScreen(api: widget.api, edit: copy),
      ),
    );
    if (!mounted) return;
    nav.pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            RouteScreen(api: widget.api, id: copy.id, title: saved is RouteDetail ? saved.title : copy.title),
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
        // Someone else's planned route (others' hikes lack their ends).
        if (!r.canEdit && r.hikedAt == null && r.line.length >= 2)
          MenuAction('copy', Icons.edit_outlined, t.routeCopy, () => _copy(r)),
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
        // A stage is ticked off on its journey.
        if (!stage)
          ...doneActions(
            context,
            widget.api,
            id: r.id,
            journey: false,
            state: _done ?? (doneOn: r.doneOn, marked: r.doneMarked),
            onDone: (s) => setState(() => _done = s),
          ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatsStrip(r.totals),
        if (_commentCount case final n? when n > 0)
          CommentsCount(count: n, onTap: () => setState(() => _tab = _Tab.comments)),
        if ((_done ?? (doneOn: r.doneOn, marked: r.doneMarked)) case (doneOn: final on?, :final marked)) ...[
          const SizedBox(height: 4),
          Text(
            key: const Key('done-on'),
            '✓ ${doneText(t, on)}${marked ? '' : ' · ${t.doneByHike}'}',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (r.official case final o?)
          OfficialLine(o)
        else if (!r.isOwner)
          OwnerLine(api: widget.api, owner: r.owner, open: true),
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

  Widget _tabBar(AppLocalizations t, List<_Tab> tabs) => PanelTabBar(
    tabs: [
      for (final tab in tabs)
        (
          id: tab.name,
          label: switch (tab) {
            _Tab.overview => t.routeTabOverview,
            _Tab.along => '${t.poisTitle} $_poiCount',
            _Tab.travel => t.routeTabTravel,
            _Tab.photos => _photoCount == null ? t.photosTitle : '${t.photosTitle} $_photoCount',
            _Tab.comments => _commentCount == null ? t.commentsTab : '${t.commentsTab} $_commentCount',
          },
        ),
    ],
    current: _tab.name,
    onTap: (id) => setState(() => _tab = _Tab.values.byName(id)),
  );

  Widget _pane(_Tab tab, Widget child) => tabPane(_tab == tab, child);

  /// A part of the route picked in a list, on the map.
  void _show(List<List<List<double>>> parts) {
    if ((_map, _style) case (final map?, final style?)) showParts(map, style, parts).catchError((_) {});
  }

  /// The place under the finger on the elevation profile, on the map.
  void _profilePoint(Geographic? at) {
    if (_style case final style?) showProfilePoint(style, at).catchError((_) {});
  }

  Widget _picture() => Hero(
    tag: routeImageTag(widget.id),
    child: RoutePicture(url: widget.image!, headers: widget.api.authHeaders),
  );

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
          if (snap.hasError) {
            return ErrorState(error: snap.error, onRetry: () => setState(() => _route = _load()));
          }
          const loading = Center(child: CircularProgressIndicator());
          if (!snap.hasData) {
            return widget.image == null ? loading : MapSplit(share: 0.5, map: _picture(), panel: loading);
          }
          final r = snap.data!;
          final pack = _pack;
          final tabs = [
            _Tab.overview,
            if (_poiCount > 0) _Tab.along,
            // A stage's way there and back is its journey's; its photos and
            // comments are on its journey too.
            if (r.line.length >= 2 && r.journeyId == null) _Tab.travel,
            if (r.journeyId == null) ...[_Tab.photos, _Tab.comments],
          ];
          return MapSplit(
            // Half the screen on a phone, so the panel keeps its height
            // between the tabs; the tab bar stays while the rest scrolls.
            share: 0.5,
            map: Stack(
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
                            initStyle: pack != null ? offlineStyle(pack.files) : swisstopoStyle(widget.api.server),
                            initCenter: Geographic(lon: view.lon, lat: view.lat),
                            initZoom: view.zoom,
                          ),
                          onEvent: _places.onEvent,
                          onMapCreated: (c) => _map = c,
                          onStyleLoaded: (style) async {
                            _style = style;
                            await _places.addTo(style);
                            await showMyLocation(_map);
                            await addRouteLine(style, r.line);
                            if (mounted) setState(() => _lineShown = true);
                            await addHighlight(style);
                            await addProfilePoint(style);
                            await _places.addAlong(style, await _pois);
                          },
                        );
                      },
                    ),
                if (widget.image != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _lineShown ? 0 : 1,
                        duration: Durations.medium4,
                        child: _picture(),
                      ),
                    ),
                  ),
                Positioned(top: 12, left: 12, right: 64, child: MapCorner(places: _places)),
                const Positioned(top: 12, right: 12, child: PlaceLayerButton()),
                Positioned(top: 64, right: 12, child: MyLocationButton(map: () => _map)),
              ],
            ),
            panel: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  sliver: SliverToBoxAdapter(child: _head(t, r, pack)),
                ),
                if (tabs.length > 1) SliverPersistentHeader(pinned: true, delegate: PinnedTabBar(_tabBar(t, tabs))),
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
                                if (offTrail(r.json)) OffTrailWarning(distanceM: r.totals.distanceM),
                                FutureBuilder(
                                  future: _steep,
                                  builder: (context, snap) {
                                    final steep = snap.data?.known == true ? snap.data : null;
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        ElevationProfile.ofLine(
                                          r.line,
                                          onPoint: _profilePoint,
                                          steep: steep?.stretches,
                                        ),
                                        if (steep != null) SteepLegend(steep),
                                      ],
                                    );
                                  },
                                ),
                                ProtectedAreas(_areas, onShow: _show),
                                SnowAlongView(_snow, onShow: _show),
                                RouteWeatherView(
                                  _weather,
                                  later: (date) => widget.api
                                      .routeWeather(widget.id, date: date)
                                      .then<RouteWeather?>((w) => w, onError: (_) => null),
                                ),
                                TrailConditions(route: r.json, distanceM: r.totals.distanceM),
                              ],
                            ),
                          ),
                          _pane(_Tab.along, PoiList(_pois, onTap: _places.markAlong)),
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
                                  PhotoStrip(
                                    api: widget.api,
                                    id: r.id,
                                    onCount: (n) => setState(() => _photoCount = n),
                                  ),
                                ],
                              ),
                            ),
                          // Likes go with the comments.
                          if (tabs.contains(_Tab.comments))
                            _pane(
                              _Tab.comments,
                              SocialPanel(api: widget.api, id: r.id, onCount: (n) => setState(() => _commentCount = n)),
                            ),
                        ],
                      ),
                    ),
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

enum _Tab { overview, along, travel, photos, comments }
