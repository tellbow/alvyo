import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../offline/packs.dart';
import 'item_card.dart';
import 'journey_plan_screen.dart';
import 'journey_screen.dart';
import 'tag_chips.dart';

/// The user's journeys; the saved ones when the server cannot be reached.
class JourneysList extends StatefulWidget {
  const JourneysList({super.key, required this.api});
  final Api api;

  @override
  State<JourneysList> createState() => _JourneysListState();
}

class _JourneysListState extends State<JourneysList> {
  late Future<(List<JourneySummary>, bool offline)> _journeys = _load();

  Future<(List<JourneySummary>, bool)> _load() async {
    try {
      return (await widget.api.journeys(), false);
    } catch (e) {
      if (e is ApiException && e.status < 500) rethrow;
      final saved = await (await PackStore.open()).savedJourneys();
      if (saved.isEmpty) rethrow;
      return ([for (final j in saved) JourneySummary.of(j)], true);
    }
  }

  void _reload() => setState(() {
    _journeys = _load();
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: FilledButton.tonalIcon(
          key: const Key('journey-plan'),
          icon: const Icon(Icons.edit_calendar_outlined),
          label: Text(AppLocalizations.of(context).jplanTitle),
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => JourneyPlanScreen(api: widget.api)));
            if (mounted) _reload();
          },
        ),
      ),
      Expanded(child: _list(context)),
    ],
  );

  Widget _list(BuildContext context) {
    final t = AppLocalizations.of(context);
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: FutureBuilder(
        future: _journeys,
        builder: (context, snap) {
          if (snap.hasError) return ListView(children: [ListTile(title: Text(t.errorServer))]);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (journeys, offline) = snap.data!;
          if (journeys.isEmpty) return ListView(children: [ListTile(title: Text(t.journeysEmpty))]);
          return ListView.builder(
            itemCount: journeys.length + (offline ? 1 : 0),
            itemBuilder: (context, i) {
              if (offline && i == 0) {
                return ListTile(
                  key: const Key('journeys-offline'),
                  leading: const Icon(Icons.cloud_off),
                  title: Text(t.journeysOffline),
                );
              }
              final j = journeys[offline ? i - 1 : i];
              return ItemCard(
                child: ListTile(
                  title: Text(j.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      Text(
                        '${t.journeyStagesCount(j.stagesDone, j.stages)} · '
                        '${formatDistance(j.distanceM)} · ${formatDuration(j.durationS)} · ↑ ${j.ascentM.round()} m',
                      ),
                      if (j.tags.isNotEmpty) TagChips(j.tags),
                    ],
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => JourneyScreen(api: widget.api, id: j.id, title: j.title),
                      ),
                    );
                    if (mounted) _reload();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
