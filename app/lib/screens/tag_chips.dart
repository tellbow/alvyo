import 'package:flutter/material.dart';

/// An item's tags, small, under its title in a list.
class TagChips extends StatelessWidget {
  const TagChips(this.tags, {super.key});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final t in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
            child: Text(t, style: Theme.of(context).textTheme.labelSmall),
          ),
      ],
    );
  }
}
