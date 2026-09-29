import 'package:flutter/material.dart';

import '../api.dart';
import '../bug_report.dart';
import '../l10n/app_localizations.dart';
import 'details.dart';
import 'item_menu.dart';
import 'item_card.dart';
import 'tiles.dart';

/// The user's collections and those shared with them.
class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key, required this.api});
  final Api api;

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  late Future<(List<CollectionSummary>, List<CollectionSummary>)> _lists = _load();

  Future<(List<CollectionSummary>, List<CollectionSummary>)> _load() async {
    final shared = widget.api.shared().then((s) => s.collections, onError: (Object _) => <CollectionSummary>[]);
    return (await widget.api.collections(), await shared);
  }

  void _reload() => setState(() {
    _lists = _load();
  });

  Future<void> _open(String id, String title) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CollectionScreen(api: widget.api, id: id, title: title),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _create() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final title = await askText(context, title: t.collectionNew, label: t.fieldTitle);
    if (title == null || title.isEmpty) return;
    try {
      final c = await widget.api.createCollection(title);
      if (mounted) await _open(c.id, c.title);
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.collectionsTitle),
        actions: [
          IconButton(
            key: const Key('collection-new'),
            tooltip: t.collectionNew,
            icon: const Icon(Icons.add),
            onPressed: _create,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder(
          future: _lists,
          builder: (context, snap) {
            if (snap.hasError) return ListView(children: [ListTile(title: Text(t.errorServer))]);
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final (mine, shared) = snap.data!;
            Widget tile(CollectionSummary c, {bool others = false}) => ItemCard(
              child: ListTile(
                key: Key('collection-${c.id}'),
                leading: const Icon(Icons.collections_bookmark_outlined),
                title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([if (others) t.ownerBy(c.owner), t.collectionItemsCount(c.items)].join(' · ')),
                onTap: () => _open(c.id, c.title),
              ),
            );
            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: Text(t.collectionsIntro)),
                if (mine.isEmpty) ListTile(title: Text(t.collectionsEmpty)),
                for (final c in mine) tile(c),
                if (shared.isNotEmpty) ListHeading(t.sharedTitle),
                for (final c in shared) tile(c, others: true),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A collection's routes and journeys; its owner and editors remove them.
class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key, required this.api, required this.id, required this.title});
  final Api api;
  final String id, title;

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> with ReportsPlace<CollectionScreen> {
  @override
  String get place => '/collections/${widget.id}';

  late Future<Collection> _collection = widget.api.collection(widget.id);

  Future<void> _remove(CollectionItem i) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final c = await widget.api.removeFromCollection(widget.id, i.id);
      if (mounted) {
        setState(() {
          _collection = Future.value(c);
        });
      }
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    }
  }

  Future<void> _delete() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await widget.api.deleteCollection(widget.id);
      nav.pop();
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FutureBuilder(
      future: _collection,
      builder: (context, snap) {
        final c = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(c?.title ?? widget.title),
            actions: [
              if (c != null && c.isOwner)
                ItemMenu(
                  actions: [
                    MenuAction(
                      'share',
                      Icons.share_outlined,
                      t.shareAction,
                      () => shareSheet(
                        context,
                        widget.api,
                        id: c.id,
                        journey: false,
                        collection: true,
                        visibility: c.visibility,
                        token: c.shareToken,
                      ),
                    ),
                  ],
                  question: t.collectionDeleteConfirm,
                  onDelete: _delete,
                ),
            ],
          ),
          body: switch (snap) {
            _ when snap.hasError => Center(child: Text(t.errorServer)),
            _ when c == null => const Center(child: CircularProgressIndicator()),
            _ => RefreshIndicator(
              onRefresh: () async {
                final next = widget.api.collection(widget.id);
                setState(() {
                  _collection = next;
                });
                await next;
              },
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (c.description.isNotEmpty)
                    Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: Text(c.description)),
                  if (c.items.isEmpty) ListTile(title: Text(t.collectionEmpty)),
                  for (final i in c.items)
                    OtherTile(
                      key: Key('item-${i.id}'),
                      journey: i.kind == 'journey',
                      title: i.title,
                      owner: i.owner,
                      distanceM: i.distanceM,
                      durationS: i.durationS,
                      ascentM: i.ascentM,
                      sacGrade: i.sacGrade,
                      sacMax: i.sacMax,
                      stages: i.stages,
                      extra: i.note.isEmpty ? null : i.note,
                      trailing: c.canEdit
                          ? IconButton(
                              key: Key('item-remove-${i.id}'),
                              tooltip: t.collectionRemoveItem,
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => _remove(i),
                            )
                          : null,
                      onTap: () async {
                        await openItem(
                          context,
                          widget.api,
                          journey: i.kind == 'journey',
                          id: i.targetId,
                          title: i.title,
                        );
                      },
                    ),
                ],
              ),
            ),
          },
        );
      },
    );
  }
}

/// Picks one of the user's collections (or a new one) and adds the route
/// or journey [id] to it.
Future<void> addToCollection(BuildContext context, Api api, String id, {required bool journey}) async {
  final t = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final List<CollectionSummary> mine;
  try {
    mine = await api.collections();
  } on Object {
    messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    return;
  }
  if (!context.mounted) return;
  const create = '';
  final chosen = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(title: Text(t.collectionAddTo, style: Theme.of(context).textTheme.titleMedium)),
          for (final c in mine)
            ListTile(
              key: Key('pick-${c.id}'),
              leading: const Icon(Icons.collections_bookmark_outlined),
              title: Text(c.title),
              subtitle: Text(t.collectionItemsCount(c.items)),
              onTap: () => Navigator.pop(context, c.id),
            ),
          ListTile(
            key: const Key('pick-new'),
            leading: const Icon(Icons.add),
            title: Text(t.collectionNew),
            onTap: () => Navigator.pop(context, create),
          ),
        ],
      ),
    ),
  );
  if (chosen == null || !context.mounted) return;
  var collectionId = chosen;
  var title = mine.where((c) => c.id == chosen).firstOrNull?.title ?? '';
  try {
    if (chosen == create) {
      final name = await askText(context, title: t.collectionNew, label: t.fieldTitle);
      if (name == null || name.isEmpty) return;
      final c = await api.createCollection(name);
      collectionId = c.id;
      title = c.title;
    }
    await api.addToCollection(collectionId, id, journey: journey);
    messenger.showSnackBar(SnackBar(content: Text(t.collectionAdded(title))));
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.status == 409 ? t.collectionAlready(title) : t.errorGeneric)));
  } on Object {
    messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
  }
}

/// Asks for one line of text; null when cancelled.
Future<String?> askText(BuildContext context, {required String title, required String label, String initial = ''}) {
  final t = AppLocalizations.of(context);
  final field = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const Key('ask-text'),
        controller: field,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          key: const Key('ask-text-ok'),
          onPressed: () => Navigator.pop(context, field.text.trim()),
          child: Text(t.save),
        ),
      ],
    ),
  );
}
