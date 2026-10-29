import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart' show Geographic;

import 'error_state.dart';
import '../analytics.dart';
import '../api.dart';
import '../bug_report.dart';
import '../elevation_profile.dart';
import '../protected_areas.dart';
import '../reminders.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../offline/downloads.dart';
import '../offline/packs.dart';
import '../travel.dart';
import '../weather.dart';
import 'collections_screen.dart';
import 'details.dart';
import 'done.dart';
import 'item_menu.dart';
import 'journey_map_screen.dart';
import 'panel_tabs.dart';
import 'people_section.dart';
import 'photos.dart';
import 'planner_screen.dart';
import 'report_dialog.dart';
import 'route_screen.dart';
import 'social.dart';
import 'stage_sheet.dart';
import 'tag_chips.dart';
import 'travel_screen.dart';
import 'wide.dart';

/// A journey's stages. Each opens as a route: its map, saving it offline,
/// hiking it; all can be saved offline at once. A stage's sheet has its
/// details, public transport and changes. Weather, areas and people, the
/// way there and back, and the photos and comments are in tabs beside the
/// stages.
class JourneyScreen extends StatefulWidget {
  const JourneyScreen({super.key, required this.api, required this.id, required this.title});
  final Api api;
  final String id;
  final String title;

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> with ReportsPlace<JourneyScreen> {
  @override
  void initState() {
    super.initState();
    Analytics.instance.screen('journey');
  }

  @override
  String get place => '/journeys/${widget.id}';

  final Future<PackStore> _store = PackStore.open();
  String _tab = 'stages';

  /// When the user finished it, as changed here; else as loaded.
  DoneState? _done;

  /// How many photos there are, once loaded (the «Fotos» tab says so).
  int? _photoCount;

  late Future<JourneyDetail> _journey = _load();
  late final Future<Along> _areas = widget.api
      .areas(journeyId: widget.id)
      .catchError((_) => (areas: <ProtectedArea>[], notices: <Notice>[]));
  late final Future<SnowAlong?> _snow = widget.api
      .snowAlong(journeyId: widget.id)
      .then<SnowAlong?>((s) => s, onError: (_) => null);

  /// A part of a stage picked in a list, shown on the map.
  final _picked = ValueNotifier<List<List<List<double>>>>(const []);
  void _showParts(List<List<List<double>>> parts) => _picked.value = [...parts];
  final _profilePoint = ValueNotifier<Geographic?>(null);

  @override
  void dispose() {
    _picked.dispose();
    _profilePoint.dispose();
    super.dispose();
  }

  /// The forecast for the stages' planned days, loaded again when they change.
  (String, Future<JourneyWeather?>)? _weather;
  Future<JourneyWeather?> _weatherFor(JourneyDetail j) {
    final key = [for (final s in j.stages) '${s.routeId}@${s.plannedDate}'].join();
    if (_weather case (final k, final w) when k == key) return w;
    final w = widget.api.journeyWeather(widget.id).then<JourneyWeather?>((w) => w, onError: (_) => null);
    _weather = (key, w);
    return w;
  }

  /// Who comes along (null: not ours to see, or offline).
  late Future<List<Person>?> _people = _loadPeople();
  List<Person> _peopleNow = const [];
  Future<List<Person>?> _loadPeople() => widget.api.people(widget.id).then<List<Person>?>((p) {
    if (mounted) setState(() => _peopleNow = p);
    return p;
  }, onError: (_) => null);

  /// The user's reminders before the start, loaded again when the days
  /// change; the phone's are scheduled from them for the owner and the
  /// people along.
  (String, Future<({bool on, DateTime? start})?>)? _reminders;
  late final Future<String?> _me = widget.api.me().then<String?>((m) => m.username, onError: (_) => null);
  Future<({bool on, DateTime? start})?> _remindersFor(JourneyDetail j) {
    final key = [for (final s in j.stages) '${s.plannedDate}${s.status}${s.booked}'].join();
    if (_reminders case (final k, final r) when k == key) return r;
    final t = AppLocalizations.of(context);
    final r = widget.api.reminders(widget.id).then<({bool on, DateTime? start})?>((r) async {
      await _schedule(t, j, r);
      return r;
    }, onError: (_) => null);
    _reminders = (key, r);
    return r;
  }

  Future<void> _schedule(AppLocalizations t, JourneyDetail j, ({bool on, DateTime? start}) r) async {
    final me = await _me;
    final along = j.isOwner || ((await _people)?.any((p) => p.username.isNotEmpty && p.username == me) ?? false);
    await PhoneReminders.instance.schedule(t, j, on: r.on && along, start: r.start);
  }

  Future<void> _setReminders(JourneyDetail j, bool on) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await widget.api.setReminders(j.id, on);
      await _schedule(t, j, r);
      if (mounted) setState(() => _reminders = (_reminders?.$1 ?? '', Future.value(r)));
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    }
  }

  /// Stage routes saved offline.
  var _saved = <String>{};

  /// While saving all: the stage (of those with a route) being saved.
  int? _saving;

  /// From the server, keeping a saved copy up to date; else the saved copy.
  Future<JourneyDetail> _load() async {
    final store = await _store;
    JourneyDetail j;
    try {
      j = await widget.api.journey(widget.id);
      if (await store.savedJourney(widget.id) != null) await store.saveJourney(j);
    } catch (e) {
      if (e is ApiException && e.status < 500) rethrow;
      final saved = await store.savedJourney(widget.id);
      if (saved == null) rethrow;
      j = saved;
    }
    await _checkSaved(j);
    return j;
  }

  Future<void> _checkSaved(JourneyDetail j) async {
    final store = await _store;
    final ids = <String>{};
    for (final s in j.stages) {
      final id = s.routeId;
      if (id != null && await store.saved(id) != null) ids.add(id);
    }
    if (mounted) setState(() => _saved = ids);
  }

  /// One stage after the other; goes on when the screen is left.
  Future<void> _saveAll(JourneyDetail j) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ids = [for (final s in j.stages) ?s.routeId];
    try {
      for (final (i, id) in ids.indexed) {
        if (mounted) setState(() => _saving = i);
        await PackDownloads.instance.save(widget.api, id);
      }
      await (await _store).saveJourney(j);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(t.offlineFailed)));
    }
    if (mounted) setState(() => _saving = null);
    await _checkSaved(j);
  }

  /// Marks a stage hiked or planned again; on a conflict shows the stage as
  /// it is now.
  Future<void> _setDone(JourneyDetail j, Stage s, bool done) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await widget.api.setStageDone(j.id, s, done);
      if (await (await _store).savedJourney(j.id) != null) await (await _store).saveJourney(updated);
      if (mounted) {
        setState(() {
          _journey = Future.value(updated);
        });
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.status == 412 ? t.stageConflict : t.errorServer)));
      if (e.status == 412 && mounted) {
        setState(() {
          _journey = _load();
        });
      }
    } on Exception {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    }
  }

  /// Shows [j] as changed; keeps a saved copy up to date.
  Future<void> _show(JourneyDetail j) async {
    final store = await _store;
    if (await store.savedJourney(j.id) != null) await store.saveJourney(j);
    if (mounted) {
      setState(() {
        _journey = Future.value(j);
      });
    }
  }

  /// Plans stage [i]'s route (it has none yet), going on from where the
  /// stage before ends.
  Future<void> _planStage(JourneyDetail j, int i) async {
    final t = AppLocalizations.of(context);
    final before = [
      for (final (k, line) in j.stageLines)
        if (k < i && line.isNotEmpty) line.last,
    ].lastOrNull;
    final s = j.stages[i];
    final saved = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        builder: (_) => PlannerScreen(
          api: widget.api,
          stage: (journeyId: j.id, stageId: s.id, title: s.title.isEmpty ? t.journeyStage(i + 1) : s.title),
          start: before == null ? null : (lon: before[0], lat: before[1]),
        ),
      ),
    );
    if (saved is JourneyDetail) await _show(saved);
  }

  /// A new stage at the end, planned at once.
  Future<void> _addStage(JourneyDetail j) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final added = await widget.api.addStage(j.id);
      await _show(added);
      if (mounted) await _planStage(added, added.stages.length - 1);
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    }
  }

  Future<void> _edit(JourneyDetail j) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final now = Details(title: j.title, description: j.description, tags: j.tags, visibility: j.visibility);
    final next = await editDetails(context, now, visibility: j.isOwner);
    if (next == null) return;
    final changes = detailChanges(now, next);
    if (changes.isEmpty) return;
    try {
      await _show(await widget.api.updateJourney(j.id, j.version, changes));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(changeError(t, e))));
      if (e is ApiException && e.status == 412 && mounted) {
        setState(() {
          _journey = _load();
        });
      }
    }
  }

  Future<void> _stage(JourneyDetail j, int i) async {
    final changed = await showStage(context, widget.api, j, i);
    if (changed != null) await _show(changed);
  }

  /// Deletes the journey on the server and what is saved of it, then
  /// leaves.
  /// «Als eigene Etappentour bearbeiten»: the user's private copy takes
  /// this journey's place, to be changed there.
  Future<void> _copy(JourneyDetail j) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final copy = await widget.api.copyJourney(j.id);
      if (!mounted) return;
      nav.pushReplacement(
        MaterialPageRoute(
          builder: (_) => JourneyScreen(api: widget.api, id: copy.id, title: copy.title),
        ),
      );
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.copyFailed)));
    }
  }

  Future<void> _delete(JourneyDetail j) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await widget.api.deleteJourney(j.id);
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
      return;
    }
    await (await _store).deleteJourney(j);
    if (mounted) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder(future: _journey, builder: (context, snap) => Text(snap.data?.title ?? widget.title)),
        actions: [
          FutureBuilder(
            future: _journey,
            builder: (context, snap) => switch (snap.data) {
              final j? => ItemMenu(
                actions: [
                  if (j.canEdit) MenuAction('edit', Icons.edit_outlined, t.editAction, () => _edit(j)),
                  if (!j.canEdit && j.stages.any((s) => s.routeId != null))
                    MenuAction('copy', Icons.edit_outlined, t.journeyCopy, () => _copy(j)),
                  if (j.isOwner)
                    MenuAction(
                      'share',
                      Icons.share_outlined,
                      t.shareAction,
                      () => shareSheet(
                        context,
                        widget.api,
                        id: j.id,
                        journey: true,
                        visibility: j.visibility,
                        token: j.shareToken,
                      ),
                    ),
                  MenuAction(
                    'gpx',
                    Icons.file_download_outlined,
                    t.gpxJourney,
                    () => shareGpx(context, widget.api, j.id, j.title, journey: true),
                  ),
                  ...doneActions(
                    context,
                    widget.api,
                    id: j.id,
                    journey: true,
                    state: _done ?? (doneOn: j.doneOn, marked: j.doneMarked),
                    onDone: (s) => setState(() => _done = s),
                  ),
                  MenuAction(
                    'collection',
                    Icons.collections_bookmark_outlined,
                    t.collectionAddTo,
                    () => addToCollection(context, widget.api, j.id, journey: true),
                  ),
                  if (!j.isOwner)
                    MenuAction(
                      'report',
                      Icons.flag_outlined,
                      t.reportAction,
                      () => report(context, widget.api, kind: 'journey', id: j.id),
                    ),
                ],
                question: t.journeyDeleteConfirm,
                onDelete: j.isOwner ? () => _delete(j) : null,
              ),
              _ => const SizedBox.shrink(),
            },
          ),
        ],
      ),
      body: FutureBuilder(
        future: _journey,
        builder: (context, snap) {
          if (snap.hasError) {
            return ErrorState(error: snap.error, onRetry: () => setState(() => _journey = _load()));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final j = snap.data!;
          final routed = [for (final s in j.stages) ?s.routeId];
          // The stages first: what is worked on most; the rest in tabs beside them.
          final tabs = [
            (id: 'stages', label: '${t.journeyTabStages} ${j.stages.length}'),
            (id: 'overview', label: t.routeTabOverview),
            (id: 'travel', label: t.routeTabTravel),
            (id: 'photos', label: _photoCount == null ? t.photosTitle : '${t.photosTitle} $_photoCount'),
          ];
          final list = RefreshIndicator(
            onRefresh: () async {
              final next = _load();
              setState(() {
                _journey = next;
                _people = _loadPeople();
              });
              await next; // the spinner stays until it is there
            },
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        StatsStrip(j.totals),
                        const SizedBox(height: 8),
                        Text(
                          key: const Key('journey-progress'),
                          t.journeyStagesCount(j.stagesDone, j.stagesTotal),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(value: j.stagesTotal == 0 ? 0 : j.stagesDone / j.stagesTotal),
                        if ((_done ?? (doneOn: j.doneOn, marked: j.doneMarked)) case (
                          doneOn: final on?,
                          :final marked,
                        )) ...[
                          const SizedBox(height: 4),
                          Text(
                            key: const Key('done-on'),
                            '✓ ${doneText(t, on)}${marked ? '' : ' · ${t.doneByStages}'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if (j.official case final o?)
                          OfficialLine(o)
                        else if (!j.isOwner && j.owner.isNotEmpty)
                          OwnerLine(api: widget.api, owner: j.owner, open: true),
                        if (j.tags.isNotEmpty) ...[const SizedBox(height: 4), TagChips(j.tags)],
                        if (j.stageLines.isNotEmpty && !isWide(context))
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              key: const Key('journey-map'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => JourneyMapScreen(api: widget.api, journey: j),
                                ),
                              ),
                              icon: const Icon(Icons.map_outlined),
                              label: Text(t.journeyMap),
                            ),
                          ),
                        if (_saving case final i?) ...[
                          Text(key: const Key('journey-saving'), t.journeySaving(i + 1, routed.length)),
                          const SizedBox(height: 4),
                          ValueListenableBuilder(
                            valueListenable: PackDownloads.instance.progress(routed[i]),
                            builder: (context, p, _) => LinearProgressIndicator(
                              value: (i + (p != null && p.downloading ? p.share : 0)) / routed.length,
                            ),
                          ),
                        ] else if (routed.isNotEmpty && routed.every(_saved.contains))
                          Row(
                            key: const Key('journey-saved'),
                            children: [const Icon(Icons.offline_pin), const SizedBox(width: 8), Text(t.journeySaved)],
                          )
                        else if (routed.isNotEmpty)
                          FilledButton.tonalIcon(
                            key: const Key('journey-save'),
                            onPressed: () => _saveAll(j),
                            icon: const Icon(Icons.download),
                            label: Text(t.journeySaveAll),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: PinnedTabBar(
                    PanelTabBar(tabs: tabs, current: _tab, onTap: (id) => setState(() => _tab = id)),
                  ),
                ),
                SliverSafeArea(
                  top: false,
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Every tab stays built: what each one loaded is kept.
                        tabPane(
                          _tab == 'stages',
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final (i, s) in j.stages.indexed)
                                _StageTile(
                                  key: Key('stage-$i'),
                                  n: i + 1,
                                  stage: s,
                                  people: [
                                    for (final p in _peopleNow)
                                      if (p.stages.contains(s.id)) p.name.isEmpty ? t.peopleInvited : p.name,
                                  ],
                                  saved: _saved.contains(s.routeId),
                                  onDone: j.canEdit && s.routeId != null ? (done) => _setDone(j, s, done) : null,
                                  onMore: () => _stage(j, i),
                                  onTap: switch (s.routeId) {
                                    final id? => () async {
                                      widget.api.shareTokenFor(id, widget.api.shareTokens[j.id]);
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => RouteScreen(
                                            api: widget.api,
                                            id: id,
                                            title: s.title.isEmpty ? t.journeyStage(i + 1) : s.title,
                                          ),
                                        ),
                                      );
                                      await _checkSaved(j); // saved or removed there
                                    },
                                    // No route yet: planned by those who may, else its details.
                                    _ => j.canEdit ? () => _planStage(j, i) : () => _stage(j, i),
                                  },
                                ),
                              if (j.canEdit)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                                  child: OutlinedButton.icon(
                                    key: const Key('journey-add-stage'),
                                    onPressed: () => _addStage(j),
                                    icon: const Icon(Icons.add),
                                    label: Text(t.journeyAddStage),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        tabPane(
                          _tab == 'overview',
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (j.description.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(key: const Key('journey-description'), j.description),
                                ],
                                const SizedBox(height: 8),
                                if (j.profile case (
                                  :final distances,
                                  :final points,
                                  :final elevations,
                                  :final breaks,
                                ) when distances.length > 1 && distances.length == elevations.length) ...[
                                  ElevationProfile(
                                    distances: distances,
                                    elevations: elevations,
                                    breaks: breaks,
                                    points: points,
                                    onPoint: (at) => _profilePoint.value = at,
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                JourneyWeatherView(_weatherFor(j)),
                                ProtectedAreas(
                                  _areas,
                                  days: [for (final s in j.stages) ?s.plannedDate],
                                  onShow: _showParts,
                                ),
                                SnowAlongView(_snow, onShow: _showParts),
                                FutureBuilder(
                                  future: _people,
                                  builder: (context, snap) => switch (snap.data) {
                                    final people? when people.isNotEmpty || j.isOwner => PeopleSection(
                                      api: widget.api,
                                      journey: j,
                                      people: people,
                                      onChanged: (p) => setState(() {
                                        _people = Future.value(p);
                                        _peopleNow = p;
                                      }),
                                    ),
                                    _ => const SizedBox.shrink(),
                                  },
                                ),
                                FutureBuilder(
                                  future: _remindersFor(j),
                                  builder: (context, snap) => switch (snap.data) {
                                    (:final on, start: _?) => SwitchListTile(
                                      key: const Key('journey-reminders'),
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(t.remindersOn),
                                      subtitle: Text(t.remindersHint),
                                      value: on,
                                      onChanged: (v) => _setReminders(j, v),
                                    ),
                                    _ => const SizedBox.shrink(),
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        tabPane(
                          _tab == 'travel',
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: TravelTiles(
                              api: widget.api,
                              ends: journeyEnds(j, start: t.travelStart, end: t.travelEnd),
                              load: () => widget.api.travel(widget.id),
                              save: (travel) => widget.api.setTravel(widget.id, travel),
                            ),
                          ),
                        ),
                        tabPane(
                          _tab == 'photos',
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                PhotoStrip(
                                  api: widget.api,
                                  id: j.id,
                                  journey: true,
                                  onCount: (n) => setState(() => _photoCount = n),
                                ),
                                SocialPanel(api: widget.api, id: j.id, journey: true),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
          // On a wide screen the stages' map beside them (requirement 73).
          if (j.stageLines.isEmpty) return list;
          return MapSplit(
            map: JourneyMap(api: widget.api, journey: j, picked: _picked, profilePoint: _profilePoint),
            panel: list,
          );
        },
      ),
    );
  }
}

class _StageTile extends StatelessWidget {
  const _StageTile({
    super.key,
    required this.n,
    required this.stage,
    this.people = const [],
    required this.saved,
    required this.onDone,
    required this.onMore,
    required this.onTap,
  });
  final int n;
  final Stage stage;

  /// The names of those who come along on it.
  final List<String> people;
  final bool saved;

  /// Opens the stage's sheet: details, public transport, changes.
  final VoidCallback onMore;

  /// Marks the stage hiked (true) or planned again; null if the user may not.
  final void Function(bool done)? onDone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final s = stage;
    final totals = s.totals;
    final lines = [
      [
        if (s.status == 'done') t.statusDone,
        if (s.status == 'skipped') t.statusSkipped,
        if (s.plannedDate case final d?) formatDate(d),
        if (totals != null)
          '${formatDistance(totals.distanceM)} · ${formatHikingTime(totals.durationS)} · '
              '↑\u00a0${formatHeight(totals.ascentM)} · ${formatSac(totals.sacGrade, totals.sacMax)}'
        else
          t.journeyNoRoute,
      ].join(' · '),
      if (s.startPlace != null || s.endPlace != null) '${s.startPlace ?? '–'} → ${s.endPlace ?? '–'}',
      if (s.gapStatus == 'transfer')
        t.gapTransfer(switch (s.transferBefore) {
          'pt' => t.transferPt,
          'cablecar' => t.transferCablecar,
          _ => t.transferOther,
        })
      else if (s.gapStatus == 'warning' || s.gapStatus == 'gap')
        t.gapWarning(formatDistance(s.gapM)),
      if (people.isNotEmpty) t.peopleOnStage(people.join(', ')),
    ];
    return ListTile(
      leading: CircleAvatar(
        child: switch (s.status) {
          'done' => Icon(Icons.check, semanticLabel: t.statusDone),
          'skipped' => Icon(Icons.redo, semanticLabel: t.statusSkipped),
          _ => Text('$n'),
        },
      ),
      title: Text(s.title.isEmpty ? t.journeyStage(n) : s.title),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: lines.join('\n')),
            if (s.accommodation.isNotEmpty) ...[const TextSpan(text: '\n'), accommodationSpan(t, s)],
          ],
        ),
      ),
      isThreeLine: lines.length > 1 || s.accommodation.isNotEmpty,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (saved) Icon(Icons.offline_pin, semanticLabel: t.offlineSaved),
          if (onDone case final set?)
            IconButton(
              key: Key('stage-done-${n - 1}'),
              isSelected: s.status == 'done',
              icon: const Icon(Icons.check_circle_outline),
              selectedIcon: const Icon(Icons.check_circle),
              tooltip: s.status == 'done' ? t.stageMarkPlanned : t.stageMarkDone,
              onPressed: () => set(s.status != 'done'),
            ),
          IconButton(
            key: Key('stage-more-${n - 1}'),
            icon: const Icon(Icons.more_horiz),
            tooltip: t.stageMore,
            onPressed: onMore,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
