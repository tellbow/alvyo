import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';

/// Before a hike: share the position with some contacts, or not. Returns
/// the share, or null when not shared (no contacts, offline, skipped).
Future<LiveShare?> askToShare(
  BuildContext context, {
  required Api api,
  required RouteDetail route,
  required Directory recordings,
}) async {
  final t = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final List<Contact> contacts;
  double pace = 1;
  try {
    contacts = await api.contacts().timeout(const Duration(seconds: 5));
    pace = (await api.me().timeout(const Duration(seconds: 5))).speedFactor;
  } on Object {
    return null; // offline: hike without sharing
  }
  if (contacts.isEmpty || !context.mounted) return null;
  final last = await _lastChosen(recordings);
  if (!context.mounted) return null;
  final choice = await showModalBottomSheet<({List<String> ids, DateTime end})>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ShareSheet(
      contacts: contacts,
      chosen: {
        for (final c in contacts)
          if (last.contains(c.id)) c.id,
      },
      end: DateTime.now().add(Duration(seconds: (route.totals.durationS * pace).round()) + const Duration(hours: 1)),
    ),
  );
  if (choice == null || choice.ids.isEmpty) return null;
  await _remember(recordings, choice.ids);
  try {
    return await api.startLive(routeId: route.id, title: route.title, contactIds: choice.ids, expectedEnd: choice.end);
  } on Object {
    messenger.showSnackBar(SnackBar(content: Text(t.liveShareFailed)));
    return null;
  }
}

File _file(Directory root) => File('${root.path}/live_contacts.json');

Future<Set<String>> _lastChosen(Directory root) async {
  try {
    return {for (final id in jsonDecode(await _file(root).readAsString()) as List) id as String};
  } on Object {
    return {};
  }
}

Future<void> _remember(Directory root, List<String> ids) async {
  await root.create(recursive: true);
  await _file(root).writeAsString(jsonEncode(ids));
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.contacts, required this.chosen, required this.end});
  final List<Contact> contacts;
  final Set<String> chosen;
  final DateTime end;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late final _chosen = {...widget.chosen};
  late var _end = widget.end;

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_end));
    if (picked == null) return;
    final now = DateTime.now();
    var end = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
    if (!end.isAfter(now)) end = end.add(const Duration(days: 1)); // tomorrow
    setState(() => _end = end);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    // Scrolls when it does not fit: many contacts, a small phone, large text.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.liveShareTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(t.liveShareIntro, style: Theme.of(context).textTheme.bodySmall),
            for (final c in widget.contacts)
              CheckboxListTile(
                key: Key('live-contact-${c.id}'),
                contentPadding: EdgeInsets.zero,
                value: _chosen.contains(c.id),
                title: Text(c.name),
                subtitle: Text(c.email),
                onChanged: (on) => setState(() => on == true ? _chosen.add(c.id) : _chosen.remove(c.id)),
              ),
            ListTile(
              key: const Key('live-end'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(t.liveShareEnd),
              trailing: Text(
                '${_end.day != DateTime.now().day ? '${formatDate(_end)} ' : ''}${formatTime(_end)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              onTap: _pickEnd,
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('live-share'),
              onPressed: _chosen.isEmpty ? null : () => Navigator.pop(context, (ids: _chosen.toList(), end: _end)),
              child: Text(t.liveShareStart),
            ),
            TextButton(
              key: const Key('live-skip'),
              onPressed: () => Navigator.pop(context),
              child: Text(t.liveShareSkip),
            ),
          ],
        ),
      ),
    );
  }
}
