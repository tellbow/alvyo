import 'package:flutter/material.dart';

import '../api.dart';
import '../elevation_profile.dart';
import '../protected_areas.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../offline/downloads.dart';
import '../offline/packs.dart';
import 'collections_screen.dart';
import 'details.dart';
import 'item_menu.dart';
import 'photos.dart';
import 'report_dialog.dart';
import 'route_screen.dart';
import 'social.dart';
import 'stage_sheet.dart';
import 'tag_chips.dart';
import 'travel_screen.dart';

/// A journey's stages. Each opens as a route: its map, saving it offline,
/// hiking it; all can be saved offline at once. A stage's sheet has its
/// details, public transport and changes; the journey's photos and
/// comments are below the stages.
class JourneyScreen extends StatefulWidget {
  const JourneyScreen({super.key, required this.api, required this.id, required this.title});
  final Api api;
  final String id;
  final String title;

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  final Future<PackStore> _store = PackStore.open();
  late Future<JourneyDetail> _journey = _load();
  late final Future<List<ProtectedArea>> _areas = widget.api
      .areas(journeyId: widget.id)
      .catchError((_) => <ProtectedArea>[]);

  /// The user's own way from home and back, and their homes by id; nothing
  /// offline.
  late Future<(JourneyTravel, Map<String, Home>)?> _travel = _loadTravel();

  Future<(JourneyTravel, Map<String, Home>)?> _loadTravel() async {
    try {
      final (travel, homes) = (await widget.api.travel(widget.id), await widget.api.homes());
      return (travel, {for (final h in homes) h.id: h});
    } on Object {
      return null;
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

  Future<void> _openTravel(JourneyDetail j, JourneyTravel travel, {required bool to}) async {
    await Navigator.of(context).push<JourneyTravel>(
      MaterialPageRoute(
        builder: (_) => TravelScreen(api: widget.api, journey: j, travel: travel, to: to),
      ),
    );
    if (mounted) {
      setState(() {
        _travel = _loadTravel(); // the homes may have changed too
      });
    }
  }

  Widget _travelTiles(AppLocalizations t, JourneyDetail j) => FutureBuilder(
    future: _travel,
    builder: (context, snap) {
      final (travel, homes) = snap.data ?? (null, const <String, Home>{});
      if (travel == null) return const SizedBox.shrink();
      Widget tile(bool to) {
        final way = to ? travel.to : travel.back;
        final home = homes[way?.homeId];
        return ListTile(
          key: Key(to ? 'travel-to' : 'travel-back'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(to ? Icons.directions_transit_outlined : Icons.home_outlined),
          title: Text(to ? t.travelTo : t.travelBack),
          subtitle: Text(
            way == null || home == null
                ? t.travelChoose
                : '${home.name} · ${way.arrive ? t.connectionsArrive : t.connectionsDepart} ${way.time}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openTravel(j, travel, to: to),
        );
      }

      return Column(children: [tile(true), tile(false)]);
    },
  );

  Future<void> _stage(JourneyDetail j, int i) async {
    final changed = await showStage(context, widget.api, j, i);
    if (changed != null) await _show(changed);
  }

  /// Deletes the journey on the server and what is saved of it, then
  /// leaves.
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
          if (snap.hasError) return Center(child: Text(t.errorServer));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final j = snap.data!;
          final routed = [for (final s in j.stages) ?s.routeId];
          return RefreshIndicator(
            onRefresh: () async {
              final next = _load();
              setState(() {
                _journey = next;
              });
              await next; // the spinner stays until it is there
            },
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${t.journeyStagesCount(j.stagesDone, j.stagesTotal)} · '
                        '${formatDistance(j.totals.distanceM)} · ${formatDuration(j.totals.durationS)} · '
                        '↑ ${j.totals.ascentM.round()} m',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (!j.isOwner && j.owner.isNotEmpty) OwnerLine(api: widget.api, owner: j.owner, open: true),
                      if (j.tags.isNotEmpty) ...[const SizedBox(height: 4), TagChips(j.tags)],
                      if (j.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(key: const Key('journey-description'), j.description),
                      ],
                      const SizedBox(height: 8),
                      if (j.profile case (
                        :final distances,
                        :final elevations,
                        :final breaks,
                      ) when distances.length > 1 && distances.length == elevations.length) ...[
                        ElevationProfile(distances: distances, elevations: elevations, breaks: breaks),
                        const SizedBox(height: 8),
                      ],
                      ProtectedAreas(_areas, days: [for (final s in j.stages) ?s.plannedDate]),
                      _travelTiles(t, j),
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
                const Divider(height: 1),
                for (final (i, s) in j.stages.indexed)
                  _StageTile(
                    key: Key('stage-$i'),
                    n: i + 1,
                    stage: s,
                    saved: _saved.contains(s.routeId),
                    onDone: j.canEdit && s.routeId != null ? (done) => _setDone(j, s, done) : null,
                    onMore: () => _stage(j, i),
                    onTap: switch (s.routeId) {
                      final id? => () async {
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
                      _ => () => _stage(j, i), // no route yet: its details
                    },
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PhotoStrip(api: widget.api, id: j.id, journey: true),
                      SocialPanel(api: widget.api, id: j.id, journey: true),
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

class _StageTile extends StatelessWidget {
  const _StageTile({
    super.key,
    required this.n,
    required this.stage,
    required this.saved,
    required this.onDone,
    required this.onMore,
    required this.onTap,
  });
  final int n;
  final Stage stage;
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
          '${formatDistance(totals.distanceM)} · ${formatDuration(totals.durationS)} · '
              '↑ ${totals.ascentM.round()} m · ${formatSac(totals.sacGrade, totals.sacMax)}'
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
      if (s.accommodation.isNotEmpty)
        '${t.stageAccommodation(s.accommodation)}${s.booked ? ' · ${t.stageBooked}' : ''}',
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
      subtitle: Text(lines.join('\n')),
      isThreeLine: lines.length > 1,
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
