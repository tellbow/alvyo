import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import 'item_card.dart';
import 'tiles.dart';
import 'user_screen.dart';

/// The user's news, newest first, a page at a time: what friends hiked and
/// published, new tours of the people they follow, comments on their own.
class FeedTab extends StatefulWidget {
  const FeedTab({super.key, required this.api});
  final Api api;

  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> {
  final _items = <FeedItem>[];
  DateTime? _next;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await widget.api.feed(before: more ? _next : null);
      if (!mounted) return;
      setState(() {
        if (!more) _items.clear();
        _items.addAll(page.items);
        _next = page.next;
      });
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: Text(t.feedIntro)),
          if (_failed) ListTile(title: Text(t.errorServer)),
          if (!_loading && !_failed && _items.isEmpty) ListTile(key: const Key('feed-empty'), title: Text(t.feedEmpty)),
          for (final (n, i) in _items.indexed) FeedEntry(key: Key('feed-$n'), api: widget.api, item: i),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_next != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                key: const Key('feed-more'),
                onPressed: () => _load(more: true),
                child: Text(t.feedMore),
              ),
            ),
        ],
      ),
    );
  }
}

/// One thing in the news: who did what, on which route or journey.
class FeedEntry extends StatelessWidget {
  const FeedEntry({super.key, required this.api, required this.item});
  final Api api;
  final FeedItem item;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final i = item;
    final did = switch (i.kind) {
      'hike' => t.feedHiked,
      'comment' => t.feedCommented,
      'journey' => t.feedPublishedJourney,
      _ => t.feedPublishedRoute,
    };
    final day = switch (i.doneOn) {
      final d? => formatDate(DateTime.parse(d)),
      _ => formatDate(i.publishedAt),
    };
    final journey = i.target == 'journey';
    void profile() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserScreen(api: api, username: i.owner),
      ),
    );
    return ItemCard(
      child: InkWell(
        onTap: i.id.isEmpty ? null : () => openItem(context, api, journey: journey, id: i.id, title: i.title),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              InkWell(
                customBorder: const CircleBorder(),
                onTap: profile,
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    initials(i.ownerName),
                    style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: i.ownerName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: ' $did'),
                          TextSpan(text: ' · $day', style: muted),
                        ],
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      i.id.isEmpty ? t.feedHikePrivate : i.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: i.id.isEmpty ? theme.colorScheme.onSurfaceVariant : null,
                      ),
                    ),
                    if (i.kind == 'comment')
                      Text('«${i.excerpt}»', maxLines: 2, overflow: TextOverflow.ellipsis, style: muted)
                    else
                      Text(
                        [
                          if (journey) t.collectionStages(i.stages),
                          formatDistance(i.distanceM),
                          formatHikingTime(i.durationS),
                          if (i.sacGrade > 0) formatSac(i.sacGrade, i.sacMax),
                        ].join(' · '),
                        style: muted,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The first letters of a name, as the avatar while there are no pictures.
String initials(String name) =>
    name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w.characters.first.toUpperCase()).join();
