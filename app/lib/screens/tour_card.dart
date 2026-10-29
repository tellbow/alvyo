import 'package:flutter/material.dart';

import '../format.dart';
import '../l10n/app_localizations.dart';
import '../theme.dart';
import 'item_card.dart';
import 'tag_chips.dart';

/// The one card for tours (requirement 69): routes, journeys and others'
/// items look alike, their kind in the line above the title.
class TourCard extends StatelessWidget {
  const TourCard({
    super.key,
    required this.kind,
    required this.title,
    required this.distanceM,
    required this.durationS,
    required this.ascentM,
    required this.onTap,
    this.journey = false,
    this.owner,
    this.sacGrade = 0,
    this.sacMax = 0,
    this.stages = 0,
    this.stagesDone,
    this.note,
    this.tags = const [],
    this.trailing,
    this.visibility,
  });

  /// «Route», «Etappentour · 6 Etappen»: in capitals above the title; a
  /// journey's in the accent colour.
  final String kind;
  final bool journey;

  /// Someone else's: «geteilt von» in [kind], the name set apart.
  final String? owner;
  final String title;
  final double distanceM, ascentM;
  final int durationS, sacGrade, sacMax;

  /// A journey's stages and how many are hiked: the bar of stages.
  final int stages;
  final int? stagesDone;

  /// A line under the figures: hiked when, a collection's note.
  final String? note;
  final List<String> tags;
  final Widget? trailing;
  final VoidCallback onTap;

  /// One's own: private, unlisted or public, as a badge.
  final String? visibility;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.labelSmall?.copyWith(
      letterSpacing: 0.8,
      fontWeight: FontWeight.w600,
      color: journey ? AlvyoColors.of(context).accent : scheme.onSurfaceVariant,
    );
    final figures = [
      formatDistance(distanceM),
      formatHikingTime(durationS),
      '↑ ${formatHeight(ascentM)}',
      if (sacGrade > 0) formatSac(sacGrade, sacMax),
    ].join(' · ');
    return ItemCard(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: kind.toUpperCase(),
                        children: [
                          if (owner case final o?)
                            TextSpan(
                              text: ' $o',
                              style: small?.copyWith(color: scheme.onSurface, letterSpacing: 0),
                            ),
                        ],
                      ),
                      style: small,
                    ),
                    Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(figures, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    if (visibility case final v?) VisibilityBadge(v),
                    if (note case final n?) Text(n, style: theme.textTheme.bodySmall),
                    if (stagesDone case final done? when stages > 0) ...[
                      const SizedBox(height: 4),
                      StageBar(done: done, total: stages),
                    ],
                    if (tags.isNotEmpty) TagChips(tags),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// A journey's stages as segments, the hiked ones filled, and «2 / 6».
class StageBar extends StatelessWidget {
  const StageBar({super.key, required this.done, required this.total});
  final int done, total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = AlvyoColors.of(context).accent;
    return Row(
      children: [
        Expanded(
          child: Row(
            spacing: 4,
            children: [
              for (var i = 0; i < total.clamp(0, 30); i++)
                Expanded(
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: i < done ? accent : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text('$done / $total', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// Who sees one's route or journey: an icon and a word, the rest on a long
/// press (feedback issue 45).
class VisibilityBadge extends StatelessWidget {
  const VisibilityBadge(this.visibility, {super.key});
  final String visibility;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (icon, label, hint) = switch (visibility) {
      'public' => (Icons.public, t.visibilityPublic, t.visibilityPublicHint),
      'unlisted' => (Icons.link, t.visibilityByLink, t.visibilityUnlistedHint),
      _ => (Icons.lock_outline, t.visibilityPrivate, t.visibilityPrivateHint),
    };
    return Tooltip(
      message: hint,
      child: Container(
        key: const Key('visibility'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            Icon(icon, size: 14, color: scheme.onSurfaceVariant),
            Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
