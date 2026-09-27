import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// The app bar's menu of something the user owns: «Löschen», asking
/// [question] first. [onDelete] runs only when confirmed.
class DeleteMenu extends StatelessWidget {
  const DeleteMenu({super.key, required this.question, required this.onDelete});
  final String question;
  final Future<void> Function() onDelete;

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
    if (ok == true) await onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      key: const Key('item-menu'),
      onSelected: (_) => _confirm(context),
      itemBuilder: (context) => [
        PopupMenuItem(
          key: const Key('item-delete'),
          value: 'delete',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline),
            title: Text(t.delete),
          ),
        ),
      ],
    );
  }
}
