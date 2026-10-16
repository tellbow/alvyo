import 'package:flutter/material.dart';

import '../theme.dart';

/// A place in the [BottomBar].
class BarItem {
  const BarItem(this.key, this.icon, this.label);
  final Key key;
  final IconData icon;
  final String label;
}

/// The floating bar at the bottom: two places, the record button in the
/// middle, two more places; each place named under its icon.
class BottomBar extends StatelessWidget {
  const BottomBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    required this.recordLabel,
    required this.onRecord,
  }) : assert(items.length == 4);

  final List<BarItem> items;
  final int selected;
  final ValueChanged<int> onSelect;
  final String recordLabel;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget place(int i) => Expanded(
      child: _Place(items[i], on: i == selected, onTap: () => onSelect(i)),
    );

    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        height: 68,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: scheme.outlineVariant),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        // The places' ink shows on the bar, not under it.
        child: Material(
          type: MaterialType.transparency,
          child: Row(
            children: [
              place(0),
              place(1),
              _RecordButton(label: recordLabel, onTap: onRecord),
              place(2),
              place(3),
            ],
          ),
        ),
      ),
    );
  }
}

/// The [BottomBar]'s places and record button in a rail on the left of a
/// wide screen (requirement 73), in the same order from the top.
class SideBar extends StatelessWidget {
  const SideBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    required this.recordLabel,
    required this.onRecord,
  }) : assert(items.length == 4);

  final List<BarItem> items;
  final int selected;
  final ValueChanged<int> onSelect;
  final String recordLabel;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget place(int i) => SizedBox(
      height: 64,
      child: _Place(items[i], on: i == selected, onTap: () => onSelect(i)),
    );

    return SafeArea(
      right: false,
      minimum: const EdgeInsets.only(left: 12, top: 12, bottom: 12),
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: 84,
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.outlineVariant),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                place(0),
                place(1),
                _RecordButton(label: recordLabel, onTap: onRecord),
                place(2),
                place(3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A place: its icon, its name under it.
class _Place extends StatelessWidget {
  const _Place(this.item, {required this.on, required this.onTap});
  final BarItem item;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Large text grows the names a little only: the bar keeps its height.
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2);
    final color = on ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: on,
      child: InkWell(
        key: item.key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, color: color),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: scaler,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: color, fontWeight: on ? FontWeight.w600 : null),
            ),
          ],
        ),
      ),
    );
  }
}

/// The record button, round in the accent colour.
class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Tooltip(
      message: label,
      child: Material(
        color: AlvyoColors.of(context).accent,
        shape: const CircleBorder(),
        child: InkWell(
          key: const Key('record'),
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox.square(
            dimension: 56,
            child: Icon(Icons.fiber_manual_record, color: AlvyoColors.onAccent, size: 26),
          ),
        ),
      ),
    ),
  );
}
