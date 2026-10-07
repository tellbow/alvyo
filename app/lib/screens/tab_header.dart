import 'package:flutter/material.dart';

import '../theme.dart';

/// The head of every tab (requirement 69): a large title on the left and
/// at most one action on the right.
class TabHeader extends StatelessWidget {
  const TabHeader(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: 32, height: 1.1),
              ),
            ),
            ?action,
          ],
        ),
      ),
    ),
  );
}

/// A header action with a word (no icon alone): «Importieren», «Alle».
class HeaderAction extends StatelessWidget {
  const HeaderAction({super.key, required this.label, required this.onPressed, this.icon});
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = AlvyoColors.of(context).accent;
    final style = TextButton.styleFrom(
      foregroundColor: Theme.of(context).brightness == Brightness.dark ? accent : Theme.of(context).colorScheme.primary,
      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
    );
    return icon == null
        ? TextButton(style: style, onPressed: onPressed, child: Text(label))
        : TextButton.icon(style: style, onPressed: onPressed, icon: Icon(icon), label: Text(label));
  }
}

/// A heading between the parts of a tab, with an action on the right.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.text, {super.key, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 8, 6),
    child: Row(
      children: [
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20))),
        ?action,
      ],
    ),
  );
}

/// An empty list: what it is for and the next step, not just «nothing».
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.text, this.action, this.onAction, this.icon});
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
    child: Column(
      spacing: 12,
      children: [
        if (icon case final i?) Icon(i, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
        Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
        if (action case final a? when onAction != null) FilledButton(onPressed: onAction, child: Text(a)),
      ],
    ),
  );
}
