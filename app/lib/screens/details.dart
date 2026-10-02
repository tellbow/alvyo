import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../l10n/app_localizations.dart';
import 'user_screen.dart';

/// Title, description, tags and (for the owner) visibility of a route or
/// journey, as they are and as changed in [editDetails].
class Details {
  const Details({required this.title, required this.description, required this.tags, required this.visibility});
  final String title, description;
  final List<String> tags;
  final String visibility;
}

/// Asks for new [Details]; null when cancelled. [tags] false for stage
/// routes, which have their journey's; [visibility] false for editors.
Future<Details?> editDetails(BuildContext context, Details now, {bool tags = true, bool visibility = true}) =>
    showModalBottomSheet<Details>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditSheet(now: now, tags: tags, visibility: visibility),
    );

class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.now, required this.tags, required this.visibility});
  final Details now;
  final bool tags, visibility;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final _title = TextEditingController(text: widget.now.title);
  late final _description = TextEditingController(text: widget.now.description);
  late final _tags = TextEditingController(text: widget.now.tags.join(', '));
  late var _visibility = widget.now.visibility;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Text(t.editAction, style: Theme.of(context).textTheme.titleLarge),
              TextField(
                key: const Key('edit-title'),
                controller: _title,
                decoration: InputDecoration(labelText: t.fieldTitle),
                textCapitalization: TextCapitalization.sentences,
              ),
              TextField(
                key: const Key('edit-description'),
                controller: _description,
                decoration: InputDecoration(labelText: t.fieldDescription),
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 8,
              ),
              if (widget.tags)
                TextField(
                  key: const Key('edit-tags'),
                  controller: _tags,
                  decoration: InputDecoration(labelText: t.tagsLabel, helperText: t.tagsHint),
                ),
              if (widget.visibility) ...[
                Text(t.fieldVisibility),
                SegmentedButton<String>(
                  key: const Key('edit-visibility'),
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 'private', label: Text(t.visibilityPrivate)),
                    ButtonSegment(value: 'unlisted', label: Text(t.visibilityUnlisted)),
                    ButtonSegment(value: 'public', label: Text(t.visibilityPublic)),
                  ],
                  selected: {_visibility},
                  onSelectionChanged: (s) => setState(() => _visibility = s.first),
                ),
              ],
              FilledButton(
                key: const Key('edit-save'),
                onPressed: () => Navigator.pop(
                  context,
                  Details(
                    // A title is needed: an emptied one stays.
                    title: _title.text.trim().isEmpty ? widget.now.title : _title.text.trim(),
                    description: _description.text.trim(),
                    tags: [
                      for (final tag in _tags.text.split(','))
                        if (tag.trim().isNotEmpty) tag.trim(),
                    ],
                    visibility: _visibility,
                  ),
                ),
                child: Text(t.save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The changes from [before] to [after] as `PATCH /routes` and `/journeys`
/// take them; tags only if [tags].
Map<String, Object?> detailChanges(Details before, Details after, {bool tags = true}) => {
  if (after.title != before.title) 'title': after.title,
  if (after.description != before.description) 'description': after.description,
  if (tags && after.tags.join(',') != before.tags.join(',')) 'tags': after.tags,
  if (after.visibility != before.visibility) 'visibility': after.visibility,
};

/// A message for a failed change of a route or journey.
String changeError(AppLocalizations t, Object e) => switch (e) {
  ApiException(status: 412) => t.saveConflict,
  ApiException(status: 403) => t.visibilityNeedsVerify,
  ApiException() => t.errorGeneric,
  _ => t.errorServer,
};

/// The file name for a route's or journey's GPX: the title with dashes as
/// «-» and other signs as spaces («Sargans – Weisstannen» stays readable).
String gpxFileName(String title, String id, {bool journey = false}) {
  final name = title
      .replaceAll(RegExp(r'\p{Pd}', unicode: true), '-')
      .replaceAll(RegExp(r'[^\p{L}\p{N} _-]+', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return '${name.isEmpty ? id : name}.${journey ? 'zip' : 'gpx'}';
}

/// Shares the route or journey as GPX (a journey: a ZIP of its stages).
Future<void> shareGpx(BuildContext context, Api api, String id, String title, {bool journey = false}) async {
  final t = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await api.gpx(id, journey: journey);
    final file = File('${(await getTemporaryDirectory()).path}/${gpxFileName(title, id, journey: journey)}');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], title: title));
  } on Object {
    messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
  }
}

/// The link others open a route or journey with: its page, for unlisted
/// ones with the share token; null while private.
String? shareUrl(
  Api api,
  String id,
  String visibility,
  String? token, {
  bool journey = false,
  bool collection = false,
}) {
  final kind = collection
      ? 'collections'
      : journey
      ? 'journeys'
      : 'routes';
  return switch (visibility) {
    'public' => '${api.server}/$kind/$id',
    'unlisted' when token != null => '${api.server}/$kind/$id?t=$token',
    _ => null,
  };
}

/// «von @user», opening the profile when it is someone else's public item.
class OwnerLine extends StatelessWidget {
  const OwnerLine({super.key, required this.api, required this.owner, required this.open});
  final Api api;
  final String owner;

  /// Whether a profile can be opened: public profiles show public items.
  final bool open;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Text(t.ownerBy(owner), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
    if (!open) return text;
    return InkWell(
      key: const Key('owner'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UserScreen(api: api, username: owner),
        ),
      ),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: text),
    );
  }
}

/// Who a route or journey is shared with, the link, and inviting more
/// people: for its owner.
Future<void> shareSheet(
  BuildContext context,
  Api api, {
  required String id,
  required bool journey,
  bool collection = false,
  required String visibility,
  required String? token,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) =>
      _ShareSheet(api: api, id: id, journey: journey, collection: collection, visibility: visibility, token: token),
);

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.api,
    required this.id,
    required this.journey,
    required this.collection,
    required this.visibility,
    required this.token,
  });
  final Api api;
  final String id;
  final bool journey, collection;
  final String visibility;
  final String? token;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late Future<List<Grant>> _grants = widget.api.grants(
    widget.id,
    journey: widget.journey,
    collection: widget.collection,
  );
  late String? _token = widget.token;
  final _who = TextEditingController();
  var _role = 'viewer';
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _who.dispose();
    super.dispose();
  }

  String _explain(AppLocalizations t, Object e) => switch (e) {
    ApiException(status: 429) => t.shareRate,
    ApiException(status: 403) => t.shareNeedsVerify,
    ApiException(:final message) when message.contains('no user') => t.shareNoUser,
    ApiException(:final message) when message.contains('yourself') => t.shareSelf,
    ApiException(:final message) when message.contains('too many') => t.shareTooMany,
    ApiException(status: 422) => t.shareBadEmail,
    ApiException() => t.errorGeneric,
    _ => t.errorServer,
  };

  Future<void> _run(Future<List<Grant>> Function() call, {VoidCallback? done}) async {
    final t = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final grants = await call();
      if (!mounted) return;
      setState(() {
        _grants = Future.value(grants);
      });
      done?.call();
    } on Object catch (e) {
      if (mounted) setState(() => _error = _explain(t, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rotate() async {
    final t = AppLocalizations.of(context);
    try {
      final token = await widget.api.rotateLink(widget.id, journey: widget.journey, collection: widget.collection);
      if (mounted) setState(() => _token = token);
    } on Object catch (e) {
      if (mounted) setState(() => _error = _explain(t, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final link = shareUrl(
      widget.api,
      widget.id,
      widget.visibility,
      _token,
      journey: widget.journey,
      collection: widget.collection,
    );
    String role(String r) => r == 'editor' ? t.roleEditor : t.roleViewer;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              Text(t.shareAction, style: Theme.of(context).textTheme.titleLarge),
              Text(t.shareLink, style: Theme.of(context).textTheme.titleSmall),
              if (link == null)
                Text(t.shareLinkHint, style: muted)
              else ...[
                SelectableText(link, key: const Key('share-link'), style: muted),
                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        key: const Key('share-send'),
                        icon: const Icon(Icons.ios_share),
                        label: Text(t.shareSend),
                        onPressed: () => SharePlus.instance.share(ShareParams(uri: Uri.parse(link))),
                      ),
                    ),
                    IconButton(
                      key: const Key('share-copy'),
                      tooltip: t.shareCopied,
                      icon: const Icon(Icons.copy),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: link));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.shareCopied)));
                        }
                      },
                    ),
                  ],
                ),
                if (widget.visibility == 'unlisted')
                  TextButton(key: const Key('share-rotate'), onPressed: _rotate, child: Text(t.shareRotate)),
                if (widget.visibility == 'unlisted') Text(t.shareRotateHint, style: muted),
              ],
              const Divider(),
              Text(t.sharePeople, style: Theme.of(context).textTheme.titleSmall),
              FutureBuilder(
                future: _grants,
                builder: (context, snap) => Column(
                  children: [
                    for (final g in snap.data ?? const <Grant>[])
                      ListTile(
                        key: Key('grant-${g.id}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(g.username.isNotEmpty ? '${g.displayName} (@${g.username})' : g.email),
                        subtitle: Text([role(g.role), if (g.username.isEmpty) t.sharePending].join(' · ')),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) => _run(
                            () => v == 'remove'
                                ? widget.api.removeGrant(
                                    widget.id,
                                    g.id,
                                    journey: widget.journey,
                                    collection: widget.collection,
                                  )
                                : widget.api.setGrantRole(
                                    widget.id,
                                    g.id,
                                    v,
                                    journey: widget.journey,
                                    collection: widget.collection,
                                  ),
                          ),
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'viewer', child: Text(t.roleViewer)),
                            PopupMenuItem(value: 'editor', child: Text(t.roleEditor)),
                            PopupMenuItem(value: 'remove', child: Text(t.shareRemove)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              TextField(
                key: const Key('share-who'),
                controller: _who,
                decoration: InputDecoration(labelText: t.shareWho),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
              ),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'viewer', label: Text(t.roleViewer)),
                  ButtonSegment(value: 'editor', label: Text(t.roleEditor)),
                ],
                selected: {_role},
                onSelectionChanged: (s) => setState(() => _role = s.first),
              ),
              if (_error case final e?) Text(e, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              FilledButton(
                key: const Key('share-invite'),
                onPressed: _busy
                    ? null
                    : () {
                        final who = _who.text.trim();
                        if (who.isEmpty) return;
                        _run(
                          () => widget.api.invite(
                            widget.id,
                            who,
                            _role,
                            journey: widget.journey,
                            collection: widget.collection,
                          ),
                          done: _who.clear,
                        );
                      },
                child: Text(t.shareInvite),
              ),
              Text(t.shareHint, style: muted),
            ],
          ),
        ),
      ),
    );
  }
}
