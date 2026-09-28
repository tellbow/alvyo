import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// An entry of an [ItemMenu] above «Löschen».
class MenuAction {
  const MenuAction(this.key, this.icon, this.label, this.onTap);
  final String key;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// The app bar's menu of a route, journey or collection: [actions], then
/// «Löschen» for what the user owns, asking [question] first. [onDelete]
/// runs only when confirmed.
class ItemMenu extends StatelessWidget {
  const ItemMenu({super.key, this.actions = const [], this.question = '', this.onDelete});
  final List<MenuAction> actions;
  final String question;
  final Future<void> Function()? onDelete;

  Future<void> _confirm(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(question),
        actions: [
          TextButton(
            key: const Key('delete-cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            key: const Key('delete-confirm'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.delete),
          ),
        ],
      ),
    );
    if (ok == true) await onDelete!();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (actions.isEmpty && onDelete == null) return const SizedBox.shrink();
    Widget entry(IconData icon, String label) =>
        ListTile(contentPadding: EdgeInsets.zero, leading: Icon(icon), title: Text(label));
    return PopupMenuButton<String>(
      key: const Key('item-menu'),
      onSelected: (v) {
        if (v == 'delete') {
          _confirm(context);
        } else {
          actions.firstWhere((a) => a.key == v).onTap();
        }
      },
      itemBuilder: (context) => [
        for (final a in actions) PopupMenuItem(key: Key('item-${a.key}'), value: a.key, child: entry(a.icon, a.label)),
        if (onDelete != null)
          PopupMenuItem(key: const Key('item-delete'), value: 'delete', child: entry(Icons.delete_outline, t.delete)),
      ],
    );
  }
}
