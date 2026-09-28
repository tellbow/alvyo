import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import 'report_dialog.dart';

/// Likes and comments of a route or journey: liking, commenting, replies
/// one level deep, editing and deleting one's own; the owner switches
/// comments off. Nothing shows offline.
class SocialPanel extends StatefulWidget {
  const SocialPanel({super.key, required this.api, required this.id, this.journey = false});
  final Api api;
  final String id;
  final bool journey;

  @override
  State<SocialPanel> createState() => _SocialPanelState();
}

class _SocialPanelState extends State<SocialPanel> {
  Social? _social;

  /// Why the user may not comment, if it is that.
  bool _unverified = false;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.api.social(widget.id, journey: widget.journey).then((s) {
      if (mounted) setState(() => _social = s);
      // Else blocked by the owner: then nothing is said.
      if (!s.canComment && s.commentsEnabled) {
        widget.api.me().then((m) {
          if (mounted) setState(() => _unverified = !m.emailVerified);
        }, onError: (Object _) {});
      }
    }, onError: (Object _) {});
  }

  Future<bool> _run(Future<Social> call) async {
    final t = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await call;
      if (mounted) setState(() => _social = s);
      return true;
    } on ApiException catch (e) {
      final error = switch (e.status) {
        429 => t.communityRate,
        403 => t.communityVerifyToComment,
        _ => t.errorGeneric,
      };
      if (mounted) setState(() => _error = error);
    } on Object {
      if (mounted) setState(() => _error = t.errorServer);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return false;
  }

  /// Asks for the text of a reply or of an edited comment.
  Future<String?> _ask(String title, {String initial = ''}) {
    final t = AppLocalizations.of(context);
    final field = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('comment-dialog-text'),
          controller: field,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
          FilledButton(
            key: const Key('comment-dialog-ok'),
            onPressed: () => Navigator.pop(context, field.text.trim()),
            child: Text(t.communityCommentSend),
          ),
        ],
      ),
    );
  }

  Future<void> _action(Comment c, String what, String thread) async {
    final t = AppLocalizations.of(context);
    final id = widget.id, journey = widget.journey;
    switch (what) {
      case 'reply':
        final text = await _ask(t.communityReply);
        if (text != null && text.isNotEmpty) {
          await _run(widget.api.comment(id, text, parentId: thread, journey: journey));
        }
      case 'edit':
        final text = await _ask(t.editAction, initial: c.body);
        if (text != null && text.isNotEmpty) {
          await _run(widget.api.editComment(id, c.id, text, journey: journey));
        }
      case 'delete':
        await _run(widget.api.deleteComment(id, c.id, journey: journey));
      case 'report':
        await report(context, widget.api, kind: 'comment', id: c.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final s = _social;
    if (s == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final threads = [
      for (final c in s.comments)
        if (c.parentId == null)
          (
            c,
            [
              for (final r in s.comments)
                if (r.parentId == c.id) r,
            ],
          ),
    ];

    Widget comment(Comment c, String thread, {bool reply = false}) => Padding(
      key: Key('comment-${c.id}'),
      padding: EdgeInsets.only(left: reply ? 24 : 0, top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${c.authorName} · @${c.authorUsername} · ${formatDate(c.createdAt)}'
                  '${c.edited ? ' · ${t.communityEdited}' : ''}',
                  style: muted,
                ),
                Text(c.body),
              ],
            ),
          ),
          PopupMenuButton<String>(
            key: Key('comment-menu-${c.id}'),
            iconSize: 18,
            onSelected: (v) => _action(c, v, thread),
            itemBuilder: (_) => [
              if (s.canComment && s.commentsEnabled) PopupMenuItem(value: 'reply', child: Text(t.communityReply)),
              if (c.canEdit) PopupMenuItem(value: 'edit', child: Text(t.editAction)),
              if (c.canDelete) PopupMenuItem(key: const Key('comment-delete'), value: 'delete', child: Text(t.delete)),
              if (!c.canEdit) PopupMenuItem(value: 'report', child: Text(t.reportAction)),
            ],
          ),
        ],
      ),
    );

    return Column(
      key: const Key('social'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              key: const Key('like'),
              tooltip: t.communityLike,
              isSelected: s.liked,
              icon: const Icon(Icons.favorite_border),
              selectedIcon: Icon(Icons.favorite, color: theme.colorScheme.primary),
              onPressed: _busy ? null : () => _run(widget.api.like(widget.id, !s.liked, journey: widget.journey)),
            ),
            Text(key: const Key('likes'), t.communityLikes(s.likes)),
            const Spacer(),
            Text(t.communityComments(s.comments.length), style: muted),
          ],
        ),
        if (s.canModerate)
          SwitchListTile(
            key: const Key('comments-enabled'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(t.communityCommentsAllowed),
            value: s.commentsEnabled,
            onChanged: _busy ? null : (v) => _run(widget.api.setComments(widget.id, v, journey: widget.journey)),
          ),
        for (final (c, replies) in threads) ...[
          comment(c, c.id),
          for (final r in replies) comment(r, c.id, reply: true),
        ],
        if (!s.commentsEnabled)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(t.communityCommentsOff, style: muted),
          )
        else if (s.canComment) ...[
          const SizedBox(height: 8),
          // In a dialog: the route screen's panel keeps its place under the keyboard.
          OutlinedButton.icon(
            key: const Key('comment-write'),
            icon: const Icon(Icons.mode_comment_outlined),
            label: Text(t.communityCommentPlaceholder),
            onPressed: _busy
                ? null
                : () async {
                    final text = await _ask(t.communityCommentSend);
                    if (text != null && text.isNotEmpty) {
                      await _run(widget.api.comment(widget.id, text, journey: widget.journey));
                    }
                  },
          ),
        ] else if (_unverified)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(t.communityVerifyToComment, style: muted),
          ),
        if (_error case final e?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(e, style: TextStyle(color: theme.colorScheme.error)),
          ),
      ],
    );
  }
}
