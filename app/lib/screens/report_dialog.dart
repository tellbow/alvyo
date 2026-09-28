import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/app_localizations.dart';

/// Reports a route, journey, comment or photo ([id]) or a user ([username])
/// to the moderators, with a reason and an optional note.
Future<void> report(BuildContext context, Api api, {required String kind, String? id, String? username}) async {
  final t = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => _ReportDialog(api: api, kind: kind, id: id, username: username),
  );
  if (sent == true) messenger.showSnackBar(SnackBar(content: Text(t.reportThanks)));
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.api, required this.kind, this.id, this.username});
  final Api api;
  final String kind;
  final String? id, username;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  var _reason = 'spam';
  final _note = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await widget.api.report(
        kind: widget.kind,
        id: widget.id,
        username: widget.username,
        reason: _reason,
        note: _note.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.status == 429 ? t.communityRate : t.errorGeneric);
    } on Object {
      if (mounted) setState(() => _error = t.errorServer);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final reasons = {
      'spam': t.reportReasonSpam,
      'offensive': t.reportReasonOffensive,
      'dangerous': t.reportReasonDangerous,
      'other': t.reportReasonOther,
    };
    return AlertDialog(
      title: Text(t.reportAction),
      content: SingleChildScrollView(
        child: RadioGroup<String>(
          groupValue: _reason,
          onChanged: (v) => setState(() => _reason = v ?? _reason),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.reportReason),
              for (final e in reasons.entries)
                RadioListTile<String>(
                  key: Key('report-${e.key}'),
                  contentPadding: EdgeInsets.zero,
                  value: e.key,
                  title: Text(e.value),
                ),
              TextField(
                key: const Key('report-note'),
                controller: _note,
                maxLines: 3,
                minLines: 1,
                maxLength: 1000,
                decoration: InputDecoration(labelText: t.reportNote),
              ),
              if (_error case final e?) Text(e, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
        FilledButton(key: const Key('report-send'), onPressed: _busy ? null : _send, child: Text(t.reportAction)),
      ],
    );
  }
}
