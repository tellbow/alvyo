import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/app_localizations.dart';

/// The contacts a hike can be shared with (see LiveSheet).
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key, required this.api});
  final Api api;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late Future<List<Contact>> _contacts = widget.api.contacts();
  final _name = TextEditingController();
  final _email = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final t = AppLocalizations.of(context);
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.addContact(_name.text.trim(), _email.text.trim());
      _name.clear();
      _email.clear();
      if (mounted) {
        setState(() {
          _contacts = widget.api.contacts();
        });
      }
    } on ApiException catch (e) {
      // The server's reasons are in English (liveapi.go).
      final error = switch (e) {
        _ when e.message.contains('already') => t.contactsDuplicate,
        _ when e.message.contains('at most') => t.contactsFull,
        _ when e.status == 422 => t.shareBadEmail,
        _ => t.errorGeneric,
      };
      if (mounted) setState(() => _error = error);
    } on Object {
      if (mounted) setState(() => _error = t.errorServer);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Contact c) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.deleteContact(c.id);
      if (mounted) {
        setState(() {
          _contacts = widget.api.contacts();
        });
      }
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.contactsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(t.contactsIntro),
          const SizedBox(height: 8),
          FutureBuilder(
            future: _contacts,
            builder: (context, snap) {
              if (snap.hasError) return Text(t.errorServer);
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              return Column(
                children: [
                  for (final c in snap.data!)
                    ListTile(
                      key: Key('contact-${c.email}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.name),
                      subtitle: Text(c.email),
                      trailing: IconButton(
                        tooltip: t.contactsRemove,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _remove(c),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('contact-name'),
            controller: _name,
            decoration: InputDecoration(labelText: t.contactsName),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('contact-email'),
            controller: _email,
            decoration: InputDecoration(labelText: t.contactsEmail),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            onSubmitted: (_) => _add(),
          ),
          if (_error case final e?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(e, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 8),
          FilledButton(key: const Key('contact-add'), onPressed: _busy ? null : _add, child: Text(t.contactsAdd)),
        ],
      ),
    );
  }
}

/// The people the user blocked, to unblock them.
class BlockedScreen extends StatefulWidget {
  const BlockedScreen({super.key, required this.api});
  final Api api;

  @override
  State<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<BlockedScreen> {
  late Future<List<UserRef>> _blocked = widget.api.blocked();

  Future<void> _unblock(UserRef u) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.block(u.username, false);
      if (mounted) {
        setState(() {
          _blocked = widget.api.blocked();
        });
      }
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.blockedTitle)),
      body: FutureBuilder(
        future: _blocked,
        builder: (context, snap) {
          if (snap.hasError) return ListView(children: [ListTile(title: Text(t.errorServer))]);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final users = snap.data!;
          if (users.isEmpty) return ListView(children: [ListTile(title: Text(t.blockedEmpty))]);
          return ListView(
            children: [
              for (final u in users)
                ListTile(
                  key: Key('blocked-${u.username}'),
                  title: Text(u.displayName),
                  subtitle: Text('@${u.username}'),
                  trailing: TextButton(onPressed: () => _unblock(u), child: Text(t.profileUnblock)),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Asks for the password (or, without one, a recent login) and deletes the
/// account; [onDeleted] then logs out.
Future<void> deleteAccount(BuildContext context, Api api, Me me, {required VoidCallback onDeleted}) async {
  final deleted = await showDialog<bool>(
    context: context,
    builder: (_) => _DeleteAccountDialog(api: api, me: me),
  );
  if (deleted == true) onDeleted();
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.api, required this.me});
  final Api api;
  final Me me;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final t = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.deleteMe(password: widget.me.hasPassword ? _password.text : null);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      final error = e.status == 403
          ? (widget.me.hasPassword ? t.accountDeleteWrong : t.accountDeleteLoginAgain)
          : t.errorGeneric;
      if (mounted) setState(() => _error = error);
    } on Object {
      if (mounted) setState(() => _error = t.errorServer);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final error = Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: Text(t.accountDeleteTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text(t.accountDeleteText),
            if (widget.me.hasPassword)
              TextField(
                key: const Key('account-delete-password'),
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(labelText: t.password),
              )
            else
              Text(t.accountDeleteRecent),
            if (_error case final e?) Text(e, style: TextStyle(color: error)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
        FilledButton(
          key: const Key('account-delete-confirm'),
          style: FilledButton.styleFrom(backgroundColor: error),
          onPressed: _busy ? null : _delete,
          child: Text(t.accountDeleteSubmit),
        ),
      ],
    );
  }
}
