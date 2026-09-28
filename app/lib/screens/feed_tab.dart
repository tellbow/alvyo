import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import 'tiles.dart';
import 'user_screen.dart';

/// New public routes and journeys of the people the user follows, newest
/// first, a page at a time.
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
          for (final i in _items)
            OtherTile(
              key: Key('feed-${i.id}'),
              journey: i.kind == 'journey',
              title: i.title,
              owner: i.ownerName,
              extra: formatDate(i.publishedAt),
              distanceM: i.distanceM,
              durationS: i.durationS,
              ascentM: i.ascentM,
              sacGrade: i.sacGrade,
              sacMax: i.sacMax,
              stages: i.stages,
              trailing: IconButton(
                tooltip: '@${i.owner}',
                icon: const Icon(Icons.person_outline),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => UserScreen(api: widget.api, username: i.owner),
                  ),
                ),
              ),
              onTap: () => openItem(context, widget.api, journey: i.kind == 'journey', id: i.id, title: i.title),
            ),
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
