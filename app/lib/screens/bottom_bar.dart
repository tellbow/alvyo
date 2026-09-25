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
/// middle, two more places.
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
    final accent = AlvyoColors.of(context).accent;
    Widget place(int i) => IconButton(
      key: items[i].key,
      onPressed: () => onSelect(i),
      tooltip: items[i].label,
      isSelected: i == selected,
      iconSize: 24,
      color: scheme.onSurfaceVariant,
      selectedIcon: Icon(items[i].icon, color: scheme.primary),
      icon: Icon(items[i].icon),
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            place(0),
            place(1),
            Semantics(
              button: true,
              label: recordLabel,
              child: Tooltip(
                message: recordLabel,
                child: Material(
                  color: accent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    key: const Key('record'),
                    customBorder: const CircleBorder(),
                    onTap: onRecord,
                    child: const SizedBox.square(
                      dimension: 56,
                      child: Icon(Icons.fiber_manual_record, color: AlvyoColors.onAccent, size: 26),
                    ),
                  ),
                ),
              ),
            ),
            place(2),
            place(3),
          ],
        ),
      ),
    );
  }
}
