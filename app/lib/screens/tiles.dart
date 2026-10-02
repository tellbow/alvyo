import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import 'item_card.dart';
import 'journey_screen.dart';
import 'route_screen.dart';
import 'tag_chips.dart';

/// Opens a route or journey; done when back from it.
Future<void> openItem(
  BuildContext context,
  Api api, {
  required bool journey,
  required String id,
  required String title,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) =>
        journey ? JourneyScreen(api: api, id: id, title: title) : RouteScreen(api: api, id: id, title: title),
  ),
);

/// A route as a card of a list; [owner] shown for others' routes.
class RouteTile extends StatelessWidget {
  const RouteTile({super.key, required this.route, required this.onTap, this.owner});
  final RouteSummary route;
  final VoidCallback onTap;
  final String? owner;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final r = route;
    return ItemCard(
      child: ListTile(
        title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        leading: r.hikedAt != null ? Icon(Icons.hiking, semanticLabel: t.routesHiked(formatDate(r.hikedAt!))) : null,
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            Text(
              '${owner != null ? '${t.ownerBy(owner!)} · ' : ''}'
              '${r.hikedAt != null ? '${t.routesHiked(formatDate(r.hikedAt!))} · ' : ''}'
              '${formatDistance(r.totals.distanceM)} · ${formatHikingTime(r.totals.durationS)} · '
              '↑\u00a0${formatHeight(r.totals.ascentM)} · ${formatSac(r.totals.sacGrade, r.totals.sacMax)}',
            ),
            if (r.tags.isNotEmpty) TagChips(r.tags),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

/// A journey as a card of a list; [owner] shown for others' journeys.
class JourneyTile extends StatelessWidget {
  const JourneyTile({super.key, required this.journey, required this.onTap, this.owner});
  final JourneySummary journey;
  final VoidCallback onTap;
  final String? owner;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final j = journey;
    return ItemCard(
      child: ListTile(
        title: Text(j.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            Text(
              '${owner != null ? '${t.ownerBy(owner!)} · ' : ''}'
              '${t.journeyStagesCount(j.stagesDone, j.stages)} · '
              '${formatDistance(j.distanceM)} · ${formatHikingTime(j.durationS)} · ↑\u00a0${formatHeight(j.ascentM)}',
            ),
            if (j.tags.isNotEmpty) TagChips(j.tags),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

/// A route or journey of someone else (feed, collections): title, owner and
/// numbers.
class OtherTile extends StatelessWidget {
  const OtherTile({
    super.key,
    required this.journey,
    required this.title,
    required this.owner,
    required this.distanceM,
    required this.durationS,
    required this.ascentM,
    required this.sacGrade,
    required this.sacMax,
    required this.stages,
    required this.onTap,
    this.extra,
    this.trailing,
  });
  final bool journey;
  final String title, owner;
  final double distanceM, ascentM;
  final int durationS, sacGrade, sacMax, stages;
  final VoidCallback onTap;

  /// Shown above the numbers, e.g. when it was published.
  final String? extra;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return ItemCard(
      child: ListTile(
        leading: Icon(journey ? Icons.flag_outlined : Icons.route_outlined),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [
            [t.ownerBy(owner), ?extra].join(' · '),
            [
              if (journey) t.collectionStages(stages),
              formatDistance(distanceM),
              formatHikingTime(durationS),
              '↑\u00a0${formatHeight(ascentM)}',
              formatSac(sacGrade, sacMax),
            ].join(' · '),
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}

/// A heading between the parts of a list.
class ListHeading extends StatelessWidget {
  const ListHeading(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}
