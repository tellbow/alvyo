import 'package:flutter/material.dart';

import 'wide.dart';

/// The map and its panel in Planen's modes (day tour, several days, reach):
/// on a phone the panel over the map, pulled up and down alike, a handle on
/// top; on a wide screen beside it on the left (requirement 73).
class PlanSheet extends StatelessWidget {
  const PlanSheet({super.key, required this.map, required this.panelKey, required this.children});

  /// The share of the height the panel starts at on a phone.
  static const initial = 0.4;

  /// The share of the map's height the panel covers at first: the maps fit
  /// what they show into the part above it.
  static double cover(BuildContext context) => isWide(context) ? 0 : initial;

  /// The map with what floats on it.
  final Widget map;
  final Key panelKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wide = isWide(context);
    Widget list(ScrollController? scroll) => ListView(
      key: panelKey,
      controller: scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(16, wide ? 16 : 8, 16, 32),
      children: [
        if (!wide)
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ...children,
      ],
    );
    return Stack(
      children: [
        // The same place either way: turning the phone keeps the map.
        Positioned(top: 0, right: 0, bottom: 0, left: wide ? panelWidth : 0, child: map),
        if (wide)
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: panelWidth,
            child: Material(
              color: scheme.surface,
              shape: Border(right: BorderSide(color: scheme.outlineVariant)),
              child: list(null),
            ),
          )
        else
          DraggableScrollableSheet(
            initialChildSize: initial,
            minChildSize: 0.15,
            maxChildSize: 0.9,
            builder: (context, scroll) => Material(
              elevation: 8,
              color: scheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: list(scroll),
            ),
          ),
      ],
    );
  }
}
