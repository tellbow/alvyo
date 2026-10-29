import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import 'details.dart';
import 'done.dart';
import 'journey_screen.dart';
import 'route_screen.dart';
import 'tour_card.dart';

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
  const RouteTile({super.key, required this.route, required this.onTap, this.owner, this.trailing});
  final RouteSummary route;
  final VoidCallback onTap;
  final String? owner;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final r = route;
    return TourCard(
      kind: owner != null ? '${t.tourRoute} · ${t.tourSharedBy}' : t.tourRoute,
      owner: owner,
      title: r.title,
      distanceM: r.totals.distanceM,
      durationS: r.totals.durationS,
      ascentM: r.totals.ascentM,
      sacGrade: r.totals.sacGrade,
      sacMax: r.totals.sacMax,
      note: r.hikedAt != null
          ? t.routesHiked(formatDate(r.hikedAt!))
          : r.doneOn != null
          ? '✓ ${doneText(t, r.doneOn!)}'
          : null,
      tags: r.tags,
      visibility: owner == null ? r.visibility : null,
      trailing: trailing,
      onTap: onTap,
    );
  }
}

/// A journey as a card of a list; [owner] shown for others' journeys.
class JourneyTile extends StatelessWidget {
  const JourneyTile({super.key, required this.journey, required this.onTap, this.owner, this.trailing});
  final JourneySummary journey;
  final VoidCallback onTap;
  final String? owner;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final j = journey;
    return TourCard(
      journey: true,
      kind: [t.tourJourney, t.collectionStages(j.stages), if (owner != null) t.tourSharedBy].join(' · '),
      owner: owner,
      title: j.title,
      distanceM: j.distanceM,
      durationS: j.durationS,
      ascentM: j.ascentM,
      stages: j.stages,
      stagesDone: j.stagesDone,
      note: j.doneOn != null ? '✓ ${doneText(t, j.doneOn!)}' : null,
      tags: j.tags,
      visibility: owner == null ? j.visibility : null,
      trailing: trailing,
      onTap: onTap,
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
    this.official,
  });
  final bool journey;
  final String title, owner;

  /// An official Wanderland route: named instead of its owner.
  final Official? official;
  final double distanceM, ascentM;
  final int durationS, sacGrade, sacMax, stages;
  final VoidCallback onTap;

  /// Shown under the numbers, e.g. when it was published.
  final String? extra;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return TourCard(
      journey: journey,
      kind: [
        if (journey) ...[t.tourJourney, t.collectionStages(stages)] else t.tourRoute,
        if (official case final o?) officialLabel(t, o) else t.tourBy,
      ].join(' · '),
      owner: official == null ? owner : null,
      title: title,
      distanceM: distanceM,
      durationS: durationS,
      ascentM: ascentM,
      sacGrade: sacGrade,
      sacMax: sacMax,
      note: extra,
      trailing: trailing,
      onTap: onTap,
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
