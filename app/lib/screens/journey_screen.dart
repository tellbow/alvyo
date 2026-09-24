import 'package:flutter/material.dart';

import '../api.dart';
import '../elevation_profile.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../offline/downloads.dart';
import '../offline/packs.dart';
import 'route_screen.dart';

/// A journey's stages. Each opens as a route: its map, saving it offline,
/// hiking it; all can be saved offline at once.
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
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
                      const SizedBox(height: 8),
                      if (j.profile case (
                        :final distances,
                        :final elevations,
                        :final breaks,
                      ) when distances.length > 1 && distances.length == elevations.length) ...[
                        ElevationProfile(distances: distances, elevations: elevations, breaks: breaks),
                        const SizedBox(height: 8),
                      ],
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
                      _ => null,
                    },
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
    required this.onTap,
  });
  final int n;
  final Stage stage;
  final bool saved;

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
        ],
      ),
      enabled: onTap != null,
      onTap: onTap,
    );
  }
}
