import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../errors.dart';
import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../place_search.dart';

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
              if (snap.hasError) return Text(errorText(t, snap.error));
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
          if (snap.hasError) return ListView(children: [ListTile(title: Text(errorText(t, snap.error)))]);
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

/// Where one sets off from and returns to by public transport: at most 5.
class HomesScreen extends StatefulWidget {
  const HomesScreen({super.key, required this.api});
  final Api api;

  @override
  State<HomesScreen> createState() => _HomesScreenState();
}

class _HomesScreenState extends State<HomesScreen> {
  late Future<List<Home>> _homes = widget.api.homes();
  final _name = TextEditingController();
  FoundPlace? _found;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final t = AppLocalizations.of(context);
    final found = _found;
    if (found == null || _name.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.addHome(_name.text.trim(), found.name, (lon: found.lon, lat: found.lat));
      _name.clear();
      if (mounted) {
        setState(() {
          _found = null;
          _homes = widget.api.homes();
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.status == 422 ? t.homesFull : t.errorGeneric);
    } on Object {
      if (mounted) setState(() => _error = t.errorServer);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Home h) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.deleteHome(h.id);
      if (mounted) {
        setState(() {
          _homes = widget.api.homes();
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
      appBar: AppBar(title: Text(t.homesTitle)),
      body: FutureBuilder(
        future: _homes,
        builder: (context, snap) {
          final homes = snap.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(t.homesIntro),
              const SizedBox(height: 8),
              if (snap.hasError) Text(errorText(t, snap.error)),
              if (homes == null && !snap.hasError) const Center(child: CircularProgressIndicator()),
              for (final h in homes ?? const <Home>[])
                ListTile(
                  key: Key('home-${h.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.home_outlined),
                  title: Text(h.name),
                  subtitle: Text(h.address),
                  trailing: IconButton(
                    tooltip: t.homesRemove,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _remove(h),
                  ),
                ),
              if (homes != null && homes.length < 5) ...[
                const SizedBox(height: 8),
                TextField(
                  key: const Key('home-name'),
                  controller: _name,
                  decoration: InputDecoration(labelText: t.homesName, hintText: t.homesNamePlaceholder),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 8),
                if (_found case final f?)
                  ListTile(
                    key: const Key('home-address'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.place_outlined),
                    title: Text(f.name),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: t.cancel,
                      onPressed: () => setState(() => _found = null),
                    ),
                  )
                else
                  PlaceSearch(api: widget.api, label: t.homesAddress, onPick: (p) => setState(() => _found = p)),
                if (_error case final e?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(e, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  key: const Key('home-add'),
                  onPressed: _busy || _found == null ? null : _add,
                  child: Text(t.homesAdd),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Personal access tokens for AI assistants (MCP) and alvyo-cli: they only
/// read. The token itself is shown once, right after creating it.
class AccessTokensScreen extends StatefulWidget {
  const AccessTokensScreen({super.key, required this.api});
  final Api api;

  @override
  State<AccessTokensScreen> createState() => _AccessTokensScreenState();
}

class _AccessTokensScreenState extends State<AccessTokensScreen> {
  late Future<List<AccessToken>> _tokens = widget.api.accessTokens();
  final _name = TextEditingController();
  String? _created;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final t = AppLocalizations.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await widget.api.createAccessToken(name);
      _name.clear();
      if (mounted) FocusScope.of(context).unfocus();
      if (mounted) {
        setState(() {
          _created = created.token;
          _tokens = widget.api.accessTokens();
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.status == 422 ? t.tokensFull : t.errorGeneric);
    } on Object {
      if (mounted) setState(() => _error = t.errorServer);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(AccessToken token) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(t.tokensRevokeConfirm(token.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          FilledButton(
            key: const Key('token-revoke-ok'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.tokensRevoke),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await widget.api.revokeAccessToken(token.id);
      if (mounted) {
        setState(() {
          _tokens = widget.api.accessTokens();
        });
      }
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: Text(t.tokensTitle)),
      body: FutureBuilder(
        future: _tokens,
        builder: (context, snap) {
          final tokens = snap.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(t.tokensIntro),
              const SizedBox(height: 8),
              Text(t.tokensMcp, style: muted),
              SelectableText('${widget.api.server}/api/v1/mcp', key: const Key('mcp-url')),
              if (_created case final token?)
                Card(
                  key: const Key('token-created'),
                  margin: const EdgeInsets.only(top: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.tokensCreated),
                        Row(
                          children: [
                            Expanded(child: SelectableText(token, key: const Key('token-value'))),
                            IconButton(
                              key: const Key('token-copy'),
                              tooltip: t.tokensCopy,
                              icon: const Icon(Icons.copy),
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: token));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.tokensCopied)));
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              if (snap.hasError) Text(errorText(t, snap.error)),
              if (tokens == null && !snap.hasError) const Center(child: CircularProgressIndicator()),
              for (final tok in tokens ?? const <AccessToken>[])
                ListTile(
                  key: Key('token-${tok.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.key_outlined),
                  title: Text(tok.name),
                  subtitle: Text(
                    [
                      t.tokensCreatedOn(formatDate(tok.createdAt)),
                      if (tok.lastUsedAt case final used?) t.tokensUsedOn(formatDate(used)) else t.tokensNeverUsed,
                    ].join(' · '),
                  ),
                  trailing: IconButton(
                    tooltip: t.tokensRevoke,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _revoke(tok),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('token-name'),
                controller: _name,
                maxLength: 60,
                decoration: InputDecoration(labelText: t.tokensName, hintText: t.tokensNamePlaceholder),
                onChanged: (_) => setState(() {}),
              ),
              if (_error case final e?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(e, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              FilledButton(
                key: const Key('token-create'),
                onPressed: _busy || _name.text.trim().isEmpty ? null : _create,
                child: Text(t.tokensCreate),
              ),
            ],
          );
        },
      ),
    );
  }
}
