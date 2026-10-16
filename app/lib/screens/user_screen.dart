import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'error_state.dart';
import '../api.dart';
import '../l10n/app_localizations.dart';
import 'friends_screen.dart';
import 'report_dialog.dart';
import 'tiles.dart';
import 'wide.dart';

/// Someone's public profile: their public routes and journeys, following
/// and blocking them.
class UserScreen extends StatefulWidget {
  const UserScreen({super.key, required this.api, required this.username});
  final Api api;
  final String username;

  @override
  State<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  late Future<Profile> _profile = widget.api.profile(widget.username);
  bool _busy = false;

  Future<void> _set(Future<void> Function() call) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await call();
      final next = widget.api.profile(widget.username);
      await next;
      if (mounted) {
        setState(() {
          _profile = next;
        });
      }
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return FutureBuilder(
      future: _profile,
      builder: (context, snap) {
        final p = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(p?.displayName ?? '@${widget.username}'),
            actions: [
              if (p != null && !p.self)
                PopupMenuButton<String>(
                  key: const Key('user-menu'),
                  onSelected: (v) => switch (v) {
                    'block' => _set(() => widget.api.block(p.username, !p.blocked)),
                    _ => report(context, widget.api, kind: 'user', username: p.username),
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      key: const Key('user-block'),
                      value: 'block',
                      child: Text(p.blocked ? t.profileUnblock : t.profileBlock),
                    ),
                    PopupMenuItem(key: const Key('user-report'), value: 'report', child: Text(t.reportAction)),
                  ],
                ),
            ],
          ),
          body: Readable(
            child: switch (snap) {
              _ when snap.hasError => ErrorState(
                error: snap.error,
                onRetry: () => setState(() => _profile = widget.api.profile(widget.username)),
              ),
              _ when p == null => const Center(child: CircularProgressIndicator()),
              _ => ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: [
                        Text(
                          '@${p.username} · '
                          '${t.profileSince(DateFormat.yMMMM(Localizations.localeOf(context).toString()).format(DateTime.parse(p.since)))}',
                        ),
                        Text(
                          key: const Key('profile-counts'),
                          '${t.profileFollowers(p.followers)} · ${t.profileFollowing(p.following)}',
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        if (p.blocked) Text(t.profileBlockedNote),
                        if (!p.self && !p.blocked) ...[
                          const SizedBox(height: 8),
                          FriendButton(
                            key: Key('friend-${p.friend}'),
                            api: widget.api,
                            username: p.username,
                            friend: p.friend,
                          ),
                          const SizedBox(height: 8),
                          p.followed
                              ? OutlinedButton(
                                  key: const Key('unfollow'),
                                  onPressed: _busy ? null : () => _set(() => widget.api.follow(p.username, false)),
                                  child: Text(t.profileUnfollow),
                                )
                              : FilledButton(
                                  key: const Key('follow'),
                                  onPressed: _busy ? null : () => _set(() => widget.api.follow(p.username, true)),
                                  child: Text(t.profileFollow),
                                ),
                        ],
                      ],
                    ),
                  ),
                  if (p.routes.isNotEmpty) ListHeading(t.profileRoutes),
                  for (final r in p.routes)
                    RouteTile(
                      route: r,
                      onTap: () => openItem(context, widget.api, journey: false, id: r.id, title: r.title),
                    ),
                  if (p.journeys.isNotEmpty) ListHeading(t.profileJourneys),
                  for (final j in p.journeys)
                    JourneyTile(
                      journey: j,
                      onTap: () => openItem(context, widget.api, journey: true, id: j.id, title: j.title),
                    ),
                ],
              ),
            },
          ),
        );
      },
    );
  }
}
