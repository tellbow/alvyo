import 'package:flutter/material.dart';

/// The panel over the map in Planen's modes (day tour, several days, reach):
/// pulled up and down alike, a handle on top.
class PlanSheet extends StatelessWidget {
  const PlanSheet({super.key, required this.panelKey, required this.children});

  /// The share of the height the panel starts at; the maps fit what they
  /// show into the part above it.
  static const initial = 0.4;

  final Key panelKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: initial,
      minChildSize: 0.15,
      maxChildSize: 0.9,
      builder: (context, scroll) => Material(
        elevation: 8,
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: ListView(
          key: panelKey,
          controller: scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
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
        ),
      ),
    );
  }
}
