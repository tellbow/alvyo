import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../analytics.dart';
import '../errors.dart';
import '../api.dart';
import '../l10n/app_localizations.dart';
import 'feed_tab.dart';
import 'item_card.dart';
import 'tab_header.dart';
import 'tiles.dart';
import 'user_screen.dart';
import 'wide.dart';

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

/// Friends: one's invite link, the requests both ways, one's friends,
/// people one might know and public profiles to discover.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, required this.api});
  final Api api;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  @override
  void initState() {
    super.initState();
    Analytics.instance.screen('friends');
  }

  late Future<FriendLists> _lists = widget.api.friends();
  late Future<String> _token = widget.api.friendLink();
  // Older servers have neither: then nothing to show.
  late Future<List<FriendRef>> _suggested = _orNone(widget.api.friendSuggestions());
  late Future<List<FriendRef>> _profiles = _orNone(widget.api.searchUsers());
  final _query = TextEditingController();
  Timer? _typing;
  List<FriendRef>? _found;

  static Future<List<FriendRef>> _orNone(Future<List<FriendRef>> f) => f.catchError((_) => <FriendRef>[]);

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
    _suggested = _orNone(widget.api.friendSuggestions());
    _profiles = _orNone(widget.api.searchUsers());
  });

  Future<void> _dismiss(String username) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.dismissSuggestion(username);
      if (mounted) {
        setState(() {
          _suggested = _orNone(widget.api.friendSuggestions());
        });
      }
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    }
  }

  // With a sentence: a bare link in a mail read as a request waiting in Alvyo.
  void _invite(String token) => SharePlus.instance.share(
    ShareParams(text: '${AppLocalizations.of(context).friendsInviteShare} ${widget.api.server}/friends/invite/$token'),
  );

  Widget _person(FriendRef f, {bool suggested = false}) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final numbers = [if (f.tours > 0) t.friendsTours(f.tours), if (f.mutual > 0) t.friendsMutual(f.mutual)].join(' · ');
    return ItemCard(
      key: Key('person-${f.username}'),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => UserScreen(api: widget.api, username: f.username),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  initials(f.displayName),
                  style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.displayName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text('@${f.username}', style: muted),
                    if (numbers.isNotEmpty) Text(numbers, style: muted),
                    const SizedBox(height: 4),
                    FriendButton(
                      key: Key('friend-of-${f.username}-${f.friend}'),
                      api: widget.api,
                      username: f.username,
                      friend: f.friend,
                      onChanged: (_) => _reload(),
                    ),
                  ],
                ),
              ),
              if (suggested)
                IconButton(
                  key: Key('dismiss-${f.username}'),
                  tooltip: t.friendsDismiss,
                  icon: const Icon(Icons.close),
                  onPressed: () => _dismiss(f.username),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: Text(t.friendsTitle)),
      body: Readable(
        child: FutureBuilder(
          future: _lists,
          builder: (context, snap) {
            final lists = snap.data;
            return ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text(t.friendsIntro)),
                FutureBuilder(
                  future: _token,
                  builder: (context, snap) => switch (snap.data) {
                    final token? => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              FilledButton.icon(
                                key: const Key('friend-link-share'),
                                icon: const Icon(Icons.ios_share),
                                label: Text(t.friendsInvite),
                                onPressed: () => _invite(token),
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
                          Text(t.friendsLinkHint, style: muted.copyWith(fontSize: 13)),
                        ],
                      ),
                    ),
                    _ => const SizedBox.shrink(),
                  },
                ),
                if (snap.hasError) ListTile(title: Text(errorText(t, snap.error))),
                if (lists != null) ...[
                  if (lists.incoming.isNotEmpty) ...[
                    ListHeading(t.friendsIncoming),
                    for (final f in lists.incoming) _person(f),
                  ],
                  ListHeading(t.friendsList),
                  if (lists.friends.isEmpty)
                    FutureBuilder(
                      future: _token,
                      builder: (context, snap) => EmptyHint(
                        key: const Key('friends-empty'),
                        icon: Icons.group_outlined,
                        text: t.friendsEmpty,
                        action: t.friendsInvite,
                        onAction: switch (snap.data) {
                          final token? => () => _invite(token),
                          _ => null,
                        },
                      ),
                    ),
                  for (final f in lists.friends) _person(f),
                ],
                FutureBuilder(
                  future: _suggested,
                  builder: (context, snap) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (snap.data case final s? when s.isNotEmpty) ...[
                        ListHeading(t.friendsSuggestions),
                        for (final f in s) _person(f, suggested: true),
                      ],
                    ],
                  ),
                ),
                if (lists != null && lists.outgoing.isNotEmpty) ...[
                  ListHeading(t.friendsOutgoing),
                  for (final f in lists.outgoing) _person(f),
                ],
                ListHeading(t.friendsDiscover),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    key: const Key('friends-search'),
                    controller: _query,
                    onChanged: _search,
                    decoration: InputDecoration(
                      labelText: t.friendsSearch,
                      helperText: t.friendsSearchHint,
                      helperMaxLines: 3,
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                ),
                FutureBuilder(
                  future: _profiles,
                  builder: (context, snap) {
                    final shown = _found ?? snap.data;
                    if (shown == null) return const SizedBox.shrink();
                    if (shown.isEmpty) return ListTile(title: Text(t.friendsNoneFound));
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [for (final f in shown) _person(f)],
                    );
                  },
                ),
              ],
            );
          },
        ),
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
      body: Readable(
        child: FutureBuilder(
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
      ),
    );
  }
}
