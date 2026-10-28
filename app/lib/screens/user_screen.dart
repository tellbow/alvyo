import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'error_state.dart';
import '../analytics.dart';
import '../api.dart';
import '../l10n/app_localizations.dart';
import 'friends_screen.dart';
import 'item_card.dart';
import 'outline.dart';
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
  @override
  void initState() {
    super.initState();
    Analytics.instance.screen('user');
  }

  late Future<Profile> _profile = widget.api.profile(widget.username);
  bool _busy = false;

  /// The journeys shown instead of the routes (the tabs).
  bool? _journeys;

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
            // The name is in the card below once loaded.
            title: p == null ? Text('@${widget.username}') : null,
            actions: [
              if (p != null)
                IconButton(
                  key: const Key('profile-share'),
                  tooltip: t.shareAction,
                  icon: const Icon(Icons.ios_share),
                  onPressed: () =>
                      SharePlus.instance.share(ShareParams(uri: Uri.parse('${widget.api.server}/u/${p.username}'))),
                ),
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
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                children: [
                  ItemCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 12,
                        children: [
                          Row(
                            spacing: 14,
                            children: [
                              // No pictures yet: the first letters of the name.
                              CircleAvatar(
                                radius: 30,
                                backgroundColor: theme.colorScheme.primaryContainer,
                                child: Text(
                                  _initials(p.displayName),
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.displayName,
                                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    Text(
                                      '@${p.username} · '
                                      '${t.profileSince(DateFormat.yMMMM(Localizations.localeOf(context).toString()).format(DateTime.parse(p.since)))}',
                                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (!p.self && !p.blocked)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                OutlinedButton(
                                  key: Key(p.followed ? 'unfollow' : 'follow'),
                                  onPressed: _busy
                                      ? null
                                      : () => _set(() => widget.api.follow(p.username, !p.followed)),
                                  child: Text(p.followed ? t.profileUnfollow : t.profileFollow),
                                ),
                                FriendButton(
                                  key: Key('friend-${p.friend}'),
                                  api: widget.api,
                                  username: p.username,
                                  friend: p.friend,
                                ),
                              ],
                            ),
                          if (p.blocked) Text(t.profileBlockedNote),
                          _Stats(
                            key: const Key('profile-counts'),
                            stats: [
                              (t.profileRoutes, p.routes.length),
                              (t.profileJourneys, p.journeys.length),
                              (t.profileStatFollowers, p.followers),
                              (t.profileStatFollowing, p.following),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (p.routes.isNotEmpty && p.journeys.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: SegmentedButton<bool>(
                        key: const Key('profile-tabs'),
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(value: false, label: Text(t.profileRoutes)),
                          ButtonSegment(value: true, label: Text(t.profileJourneys)),
                        ],
                        selected: {_journeys ?? false},
                        onSelectionChanged: (s) => setState(() => _journeys = s.first),
                      ),
                    )
                  else
                    const SizedBox(height: 8),
                  if (!(_journeys ?? p.routes.isEmpty))
                    for (final r in p.routes)
                      RouteTile(
                        route: r,
                        trailing: _outline(p, r.id),
                        onTap: () => openItem(context, widget.api, journey: false, id: r.id, title: r.title),
                      )
                  else
                    for (final j in p.journeys)
                      JourneyTile(
                        journey: j,
                        trailing: _outline(p, j.id),
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

String _initials(String name) =>
    name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w.characters.first.toUpperCase()).join();

Widget? _outline(Profile p, String id) => switch (p.outlines[id]) {
  final lines? when lines.isNotEmpty => Padding(padding: const EdgeInsets.only(left: 8), child: Outline(lines)),
  _ => null,
};

/// The profile's numbers as small tiles, two or four in a row.
class _Stats extends StatelessWidget {
  const _Stats({super.key, required this.stats});
  final List<(String, int)> stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget tile((String, int) s) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${s.$2}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            Text(
              s.$1,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth >= 480 ? 4 : 2;
        return Column(
          spacing: 8,
          children: [
            for (var i = 0; i < stats.length; i += perRow)
              Row(spacing: 8, children: [for (final s in stats.skip(i).take(perRow)) tile(s)]),
          ],
        );
      },
    );
  }
}
