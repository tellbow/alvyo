import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../navigation/gps.dart';
import '../sbb.dart';
import 'connections_screen.dart';

/// A stage's day, accommodation and notes, how to get there and back by
/// public transport, and (for those who may) changing it. Pops with the
/// journey when the stage was changed.
Future<JourneyDetail?> showStage(BuildContext context, Api api, JourneyDetail journey, int index) =>
    showModalBottomSheet<JourneyDetail>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _StageSheet(api: api, journey: journey, index: index),
    );

class _StageSheet extends StatefulWidget {
  const _StageSheet({required this.api, required this.journey, required this.index});
  final Api api;
  final JourneyDetail journey;
  final int index;

  @override
  State<_StageSheet> createState() => _StageSheetState();
}

class _StageSheetState extends State<_StageSheet> {
  Stage get _stage => widget.journey.stages[widget.index];
  bool _editing = false;
  bool _busy = false;
  String? _error;

  late final _accommodation = TextEditingController(text: _stage.accommodation);
  late final _notes = TextEditingController(text: _stage.notes);
  late DateTime? _date = _stage.plannedDate;
  late String _status = _stage.status;
  late bool _booked = _stage.booked;
  late String _transfer = _stage.transferBefore ?? '';

  @override
  void dispose() {
    _accommodation.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// The day to look up connections on: the planned one, else today.
  DateTime get _day => _stage.plannedDate ?? DateTime.now();

  /// The end of the stage before, when the gap to this one is covered by
  /// public transport between two stops.
  Place? get _transferFrom {
    final s = _stage;
    if (s.transferBefore != 'pt' || s.start?.kind != 'pt_stop') return null;
    final before = widget.journey.stages.take(widget.index).where((p) => p.routeId != null).lastOrNull;
    return before?.end?.kind == 'pt_stop' ? before!.end : null;
  }

  void _connections(Place from, Place to) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ConnectionsScreen(api: widget.api, from: from, to: to, day: _day),
    ),
  );

  /// From the stop nearest to the phone to the stage's start.
  Future<void> _fromHere(Place to) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final here = await knownPosition() ?? (await locationAllowed() ? await knownPosition() : null);
      if (here == null) {
        messenger.showSnackBar(SnackBar(content: Text(t.connectionsNoPosition)));
        return;
      }
      final stops = await widget.api.placesNearby(here, kinds: ['pt_stop'], limit: 1);
      if (!mounted) return;
      if (stops.isEmpty || stops.first.ref.isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(t.connectionsNone)));
        return;
      }
      _connections(stops.first, to);
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final s = _stage;
    String day(DateTime? d) => d == null
        ? ''
        : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final changes = <String, Object?>{
      if (day(_date) != day(s.plannedDate)) 'planned_date': day(_date),
      if (_status != s.status) 'status': _status,
      if (_accommodation.text.trim() != s.accommodation) 'accommodation': _accommodation.text.trim(),
      if (_booked != s.booked) 'accommodation_booked': _booked,
      if (_notes.text.trim() != s.notes) 'notes': _notes.text.trim(),
      if (_transfer != (s.transferBefore ?? '')) 'transfer_before': _transfer,
    };
    if (changes.isEmpty) {
      setState(() => _editing = false);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final j = await widget.api.updateStage(widget.journey.id, s, changes);
      if (mounted) Navigator.pop(context, j);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.status == 412 ? t.stageConflict : t.errorGeneric);
    } on Object {
      if (mounted) setState(() => _error = t.errorServer);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = _stage;
    final language = Localizations.localeOf(context).languageCode;
    final transferFrom = _transferFrom;
    Widget link(Key key, String label, Uri uri) => ListTile(
      key: key,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.train_outlined),
      title: Text(label),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 4,
            children: [
              Text(s.title.isEmpty ? t.journeyStage(widget.index + 1) : s.title, style: theme.textTheme.titleLarge),
              if (s.startPlace != null || s.endPlace != null) Text('${s.startPlace ?? '–'} → ${s.endPlace ?? '–'}'),
              if (_editing)
                ..._form(t)
              else ...[
                if (s.plannedDate case final d?) Text('${t.stageDate}: ${formatDate(d)}'),
                if (s.accommodation.isNotEmpty)
                  Text('${t.stageAccommodation(s.accommodation)}${s.booked ? ' · ${t.stageBooked}' : ''}'),
                if (s.notes.isNotEmpty) Text(key: const Key('stage-notes'), s.notes),
                if (widget.journey.canEdit)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('stage-edit'),
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(t.stageEdit),
                      onPressed: () => setState(() => _editing = true),
                    ),
                  ),
                const Divider(),
                if (transferFrom != null && transferFrom.ref.isNotEmpty && s.start!.ref.isNotEmpty)
                  ListTile(
                    key: const Key('stage-transfer-connections'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.directions_transit_outlined),
                    title: Text(t.connectionsShow),
                    subtitle: Text('${transferFrom.name} → ${s.start!.name}'),
                    onTap: () => _connections(transferFrom, s.start!),
                  ),
                if (s.start case final start? when start.kind == 'pt_stop' && start.ref.isNotEmpty)
                  ListTile(
                    key: const Key('stage-from-here'),
                    contentPadding: EdgeInsets.zero,
                    enabled: !_busy,
                    leading: const Icon(Icons.near_me_outlined),
                    title: Text(t.connectionsFromHere),
                    subtitle: Text(start.name),
                    onTap: () => _fromHere(start),
                  ),
                if (transferFrom != null)
                  link(
                    const Key('sbb-transfer'),
                    t.sbbTransfer,
                    sbbTimetable(from: transferFrom.name, to: s.start!.name, date: s.plannedDate, language: language),
                  ),
                if (s.start case final p? when p.kind == 'pt_stop')
                  link(
                    const Key('sbb-start'),
                    t.sbbToStart,
                    sbbTimetable(to: p.name, date: s.plannedDate, language: language),
                  ),
                if (s.end case final p? when p.kind == 'pt_stop')
                  link(
                    const Key('sbb-end'),
                    t.sbbFromEnd,
                    sbbTimetable(from: p.name, date: s.plannedDate, language: language),
                  ),
              ],
              if (_error case final e?) Text(e, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _form(AppLocalizations t) => [
    const SizedBox(height: 8),
    Row(
      children: [
        Expanded(child: Text('${t.stageDate}: ${_date == null ? t.stageDateNone : formatDate(_date!)}')),
        TextButton(
          key: const Key('stage-date'),
          onPressed: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _date ?? now,
              firstDate: DateTime(now.year - 5),
              lastDate: DateTime(now.year + 5),
            );
            if (picked != null) setState(() => _date = picked);
          },
          child: Text(t.editAction),
        ),
        if (_date != null)
          IconButton(
            tooltip: t.stageDateNone,
            icon: const Icon(Icons.clear),
            onPressed: () => setState(() => _date = null),
          ),
      ],
    ),
    Text(t.stageStatus),
    SegmentedButton<String>(
      key: const Key('stage-status'),
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: 'planned', label: Text(t.statusPlanned)),
        ButtonSegment(value: 'done', label: Text(t.statusDone)),
        ButtonSegment(value: 'skipped', label: Text(t.statusSkipped)),
      ],
      selected: {_status},
      onSelectionChanged: (v) => setState(() => _status = v.first),
    ),
    const SizedBox(height: 8),
    TextField(
      key: const Key('stage-accommodation'),
      controller: _accommodation,
      decoration: InputDecoration(labelText: t.stageAccommodationLabel, hintText: t.stageAccommodationPlaceholder),
    ),
    SwitchListTile(
      key: const Key('stage-booked'),
      contentPadding: EdgeInsets.zero,
      title: Text(t.stageBookedLabel),
      value: _booked,
      onChanged: (v) => setState(() => _booked = v),
    ),
    TextField(
      key: const Key('stage-notes-field'),
      controller: _notes,
      minLines: 2,
      maxLines: 6,
      decoration: InputDecoration(labelText: t.stageNotes),
    ),
    if (widget.index > 0) ...[
      const SizedBox(height: 8),
      DropdownMenu<String>(
        key: const Key('stage-transfer'),
        label: Text(t.stageTransfer),
        expandedInsets: EdgeInsets.zero,
        initialSelection: _transfer,
        onSelected: (v) => setState(() => _transfer = v ?? ''),
        dropdownMenuEntries: [
          DropdownMenuEntry(value: '', label: t.transferNone),
          DropdownMenuEntry(value: 'pt', label: t.transferPt),
          DropdownMenuEntry(value: 'cablecar', label: t.transferCablecar),
          DropdownMenuEntry(value: 'other', label: t.transferOther),
        ],
      ),
    ],
    const SizedBox(height: 8),
    FilledButton(key: const Key('stage-save'), onPressed: _busy ? null : _save, child: Text(t.save)),
  ];
}
