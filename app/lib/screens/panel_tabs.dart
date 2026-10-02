import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';

/// The four numbers of a route or journey in one row, the value above its
/// name; on the narrowest phone what does not fit shrinks.
class StatsStrip extends StatelessWidget {
  const StatsStrip(this.totals, {super.key});
  final Totals totals;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final strong = theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);
    Widget stat(String label, String value) => Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: strong),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
    return Container(
      key: const Key('route-stats'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        spacing: 4,
        children: [
          stat(t.statTime, formatHikingTime(totals.durationS)),
          stat(t.statDistance, formatDistance(totals.distanceM)),
          stat(t.statHeights, '↑${totals.ascentM.round()} ↓${totals.descentM.round()}'),
          stat(t.statSac, formatSac(totals.sacGrade, totals.sacMax)),
        ],
      ),
    );
  }
}

/// A screen's parts as tabs, with the chosen one underlined; tapping one
/// calls [onTap] with its id. Each tab's key is `tab-<id>`.
class PanelTabBar extends StatelessWidget {
  const PanelTabBar({super.key, required this.tabs, required this.current, required this.onTap});
  final List<({String id, String label})> tabs;
  final String current;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              for (final (:id, :label) in tabs)
                InkWell(
                  key: Key('tab-$id'),
                  onTap: () => onTap(id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: id == current ? theme.colorScheme.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: id == current ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                        fontWeight: id == current ? FontWeight.w600 : FontWeight.w400,
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
}

/// A tab bar pinned to the top of a scroll view while the rest scrolls.
class PinnedTabBar extends SliverPersistentHeaderDelegate {
  PinnedTabBar(this.child);
  final Widget child;

  @override
  double get minExtent => 46;

  @override
  double get maxExtent => 46;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => SizedBox.expand(child: child);

  @override
  bool shouldRebuild(PinnedTabBar old) => true;
}

/// A tab's content, kept (with what it loaded) while another is shown.
Widget tabPane(bool shown, Widget child) => Visibility(visible: shown, maintainState: true, child: child);
