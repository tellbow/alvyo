import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../errors.dart';
import '../api.dart';
import '../l10n/app_localizations.dart';
import 'tiles.dart';
import 'user_screen.dart';

/// Asking, accepting, declining and ending a friendship with [username];
/// [onChanged] gets the state afterwards.
class FriendButton extends StatefulWidget {
  const FriendButton({super.key, required this.api, required this.username, required this.friend, this.onChanged});
  final Api api;
  final String username;

  /// none, requested (by the user), incoming (to the user) or friends.
  final String friend;
  final ValueChanged<String>? onChanged;

  @override
  State<FriendButton> createState() => _FriendButtonState();
}

class _FriendButtonState extends State<FriendButton> {
  late String _friend = widget.friend;
  bool _busy = false;

  Future<void> _set(bool on) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final next = await widget.api.friend(widget.username, on);
      if (!mounted) return;
      setState(() => _friend = next);
      widget.onChanged?.call(next);
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final on = _busy ? null : () => _set(true);
    final off = _busy ? null : () => _set(false);
    return Wrap(
      key: Key('friend-$_friend'),
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: switch (_friend) {
        'none' => [FilledButton(key: const Key('friend-add'), onPressed: on, child: Text(t.friendAdd))],
        'requested' => [
          Text(t.friendRequested),
          TextButton(key: const Key('friend-withdraw'), onPressed: off, child: Text(t.friendWithdraw)),
        ],
        'incoming' => [
          FilledButton(key: const Key('friend-accept'), onPressed: on, child: Text(t.friendAccept)),
          TextButton(key: const Key('friend-decline'), onPressed: off, child: Text(t.friendDecline)),
        ],
        _ => [
          Text('✓ ${t.friendFriends}'),
          TextButton(key: const Key('friend-remove'), onPressed: off, child: Text(t.friendRemove)),
        ],
      },
    );
  }
}

/// Friends: finding public profiles, the requests both ways, one's friends
/// and one's invite link.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, required this.api});
  final Api api;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  late Future<FriendLists> _lists = widget.api.friends();
  late Future<String> _token = widget.api.friendLink();
  final _query = TextEditingController();
  Timer? _typing;
  List<FriendRef>? _found;

  @override
  void dispose() {
    _typing?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// Searched once typing pauses.
  void _search(String q) {
    _typing?.cancel();
    final term = q.trim();
    if (term.length < 2) {
      setState(() => _found = null);
      return;
    }
    _typing = Timer(const Duration(milliseconds: 300), () async {
      try {
        final found = await widget.api.searchUsers(term);
        if (mounted && _query.text.trim() == term) setState(() => _found = found);
      } on Object {
        // offline: no results
      }
    });
  }

  void _reload() => setState(() {
    _lists = widget.api.friends();
  });

  Widget _person(FriendRef f) => ListTile(
    key: Key('person-${f.username}'),
    title: Text(f.displayName),
    subtitle: Text('@${f.username}'),
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserScreen(api: widget.api, username: f.username),
      ),
    ),
    trailing: FriendButton(
      key: Key('friend-of-${f.username}-${f.friend}'),
      api: widget.api,
      username: f.username,
      friend: f.friend,
      onChanged: (_) => _reload(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: Text(t.friendsTitle)),
      body: FutureBuilder(
        future: _lists,
        builder: (context, snap) {
          final lists = snap.data;
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  key: const Key('friends-search'),
                  controller: _query,
                  onChanged: _search,
                  decoration: InputDecoration(
                    labelText: t.friendsSearch,
                    helperText: t.friendsSearchHint,
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
              ),
              if (_found case final found?)
                if (found.isEmpty) ListTile(title: Text(t.friendsNoneFound)) else for (final f in found) _person(f),
              if (snap.hasError) ListTile(title: Text(errorText(t, snap.error))),
              if (lists != null) ...[
                if (lists.incoming.isNotEmpty) ...[
                  ListHeading(t.friendsIncoming),
                  for (final f in lists.incoming) _person(f),
                ],
                ListHeading(t.friendsList),
                if (lists.friends.isEmpty) ListTile(title: Text(t.friendsEmpty, style: muted)),
                for (final f in lists.friends) _person(f),
                if (lists.outgoing.isNotEmpty) ...[
                  ListHeading(t.friendsOutgoing),
                  for (final f in lists.outgoing) _person(f),
                ],
              ],
              ListHeading(t.friendsLinkTitle),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(t.friendsLinkHint, style: muted),
              ),
              FutureBuilder(
                future: _token,
                builder: (context, snap) => switch (snap.data) {
                  final token? => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          key: const Key('friend-link-share'),
                          icon: const Icon(Icons.ios_share),
                          label: Text(t.friendsLinkShare),
                          onPressed: () => SharePlus.instance.share(
                            ShareParams(uri: Uri.parse('${widget.api.server}/friends/invite/$token')),
                          ),
                        ),
                        TextButton(
                          key: const Key('friend-link-renew'),
                          onPressed: () => setState(() {
                            _token = widget.api.friendLink(renew: true);
                          }),
                          child: Text(t.friendsLinkRenew),
                        ),
                      ],
                    ),
                  ),
                  _ => const SizedBox.shrink(),
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Someone's invite link, opened in the app: who sent it, and becoming
/// friends with one tap (as the website's /friends/invite/{token}).
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key, required this.api, required this.token});
  final Api api;
  final String token;

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  late final Future<(({String username, String displayName})?, String)> _load = () async {
    final me = await widget.api.me();
    try {
      return (await widget.api.friendInviter(widget.token), me.username);
    } on ApiException catch (e) {
      if (e.status == 404) return (null, me.username);
      rethrow;
    }
  }();
  bool _busy = false, _done = false, _failed = false;

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    var ok = true;
    try {
      await widget.api.acceptFriendInvite(widget.token);
    } on Object {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _done = ok;
      _failed = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.friendsTitle)),
      body: FutureBuilder(
        future: _load,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(t.errorGeneric));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (inviter, me) = snap.data!;
          return ListView(
            key: const Key('friend-invite'),
            padding: const EdgeInsets.all(24),
            children: [
              if (inviter == null)
                Text(t.inviteInvalid)
              else ...[
                Text(t.inviteTitle(inviter.displayName), style: theme.textTheme.headlineSmall),
                Text('@${inviter.username}', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                Text(t.inviteText),
                const SizedBox(height: 24),
                if (inviter.username == me)
                  Text(t.inviteSelf)
                else if (_done) ...[
                  Text(t.inviteDone, key: const Key('friend-invite-done'), style: theme.textTheme.titleMedium),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => UserScreen(api: widget.api, username: inviter.username),
                        ),
                      ),
                      child: Text('@${inviter.username}'),
                    ),
                  ),
                ] else ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      key: const Key('friend-invite-accept'),
                      onPressed: _busy ? null : _accept,
                      child: Text(t.inviteAccept),
                    ),
                  ),
                  if (_failed)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(t.errorGeneric, style: TextStyle(color: theme.colorScheme.error)),
                    ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}
