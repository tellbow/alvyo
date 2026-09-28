import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/app_localizations.dart';
import '../offline/packs.dart';
import 'journey_plan_screen.dart';
import 'journey_screen.dart';
import 'tiles.dart';

/// The user's journeys (the saved ones when the server cannot be reached)
/// and those shared with them.
class JourneysList extends StatefulWidget {
  const JourneysList({super.key, required this.api});
  final Api api;

  @override
  State<JourneysList> createState() => _JourneysListState();
}

class _JourneysListState extends State<JourneysList> {
  late Future<(List<JourneySummary>, bool offline)> _journeys = _load();
  late Future<List<JourneySummary>> _shared = _loadShared();

  Future<List<JourneySummary>> _loadShared() =>
      widget.api.shared().then((s) => s.journeys, onError: (Object _) => <JourneySummary>[]);

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
    _shared = _loadShared();
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
          return FutureBuilder(
            future: offline ? Future.value(<JourneySummary>[]) : _shared,
            builder: (context, sharedSnap) {
              final shared = sharedSnap.data ?? const <JourneySummary>[];
              return ListView(
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  if (offline)
                    ListTile(
                      key: const Key('journeys-offline'),
                      leading: const Icon(Icons.cloud_off),
                      title: Text(t.journeysOffline),
                    ),
                  if (journeys.isEmpty) ListTile(title: Text(t.journeysEmpty)),
                  for (final j in journeys) JourneyTile(journey: j, onTap: () => _open(j)),
                  if (shared.isNotEmpty) ListHeading(t.sharedTitle),
                  for (final j in shared) JourneyTile(journey: j, owner: j.owner, onTap: () => _open(j)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _open(JourneySummary j) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JourneyScreen(api: widget.api, id: j.id, title: j.title),
      ),
    );
    if (mounted) _reload();
  }
}
