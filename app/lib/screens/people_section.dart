import 'package:flutter/material.dart';

import '../api.dart';
import '../avatar.dart';
import '../l10n/app_localizations.dart';

/// Who comes along on a journey, as on the website: the owner adds people
/// (someone without access is invited as a viewer) and removes them; the
/// owner and editors choose their stages, each person in a sheet.
class PeopleSection extends StatefulWidget {
  const PeopleSection({
    super.key,
    required this.api,
    required this.journey,
    required this.people,
    required this.onChanged,
    this.focus,
  });
  final Api api;
  final JourneyDetail journey;
  final List<Person> people;
  final void Function(List<Person> people) onChanged;

  /// Focused by «Leute einladen» at the top of the journey.
  final FocusNode? focus;

  @override
  State<PeopleSection> createState() => _PeopleSectionState();
}

class _PeopleSectionState extends State<PeopleSection> {
  final _who = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _who.dispose();
    super.dispose();
  }

  Future<bool> _run(Future<List<Person>> call) async {
    final t = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final people = await call;
      widget.onChanged(people);
      if (mounted) setState(() => _busy = false);
      return true;
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = switch (e) {
            ApiException(status: 422) => t.peopleUnknown,
            ApiException(status: 403) => t.peopleVerify,
            _ => t.peopleFailed,
          };
        });
      }
      return false;
    }
  }

  Future<void> _add() async {
    final who = _who.text.trim();
    if (who.isEmpty) return;
    if (await _run(widget.api.addPerson(widget.journey.id, who))) _who.clear();
  }

  /// A person's stages to tick, and (owner) not coming along any more.
  Future<void> _edit(Person p) async {
    final t = AppLocalizations.of(context);
    final j = widget.journey;
    var chosen = {...p.stages};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              ListTile(title: Text(t.peopleStages(_name(t, p)), style: Theme.of(context).textTheme.titleMedium)),
              for (final (i, s) in j.stages.indexed)
                CheckboxListTile(
                  key: Key('person-stage-$i'),
                  value: chosen.contains(s.id),
                  title: Text(s.title.isEmpty ? t.journeyStage(i + 1) : '${i + 1}. ${s.title}'),
                  onChanged: (on) async {
                    final next = [
                      for (final st in j.stages)
                        if (st.id == s.id ? on == true : chosen.contains(st.id)) st.id,
                    ];
                    setSheet(() => chosen = next.toSet());
                    await _run(widget.api.setPersonStages(j.id, p.id, next));
                  },
                ),
              if (j.isOwner)
                ListTile(
                  key: const Key('person-remove'),
                  leading: const Icon(Icons.person_remove_outlined),
                  title: Text(t.peopleRemove),
                  onTap: () async {
                    Navigator.pop(context);
                    await _run(widget.api.removePerson(j.id, p.id));
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _name(AppLocalizations t, Person p) => p.name.isEmpty ? t.peopleInvited : p.name;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final j = widget.journey;
    return Column(
      key: const Key('journey-people'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(t.peopleTitle, style: theme.textTheme.labelMedium),
        if (widget.people.isEmpty) Text(t.peopleNone, style: theme.textTheme.bodySmall),
        for (final p in widget.people)
          ListTile(
            key: Key('person-${p.id}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Avatar(widget.api, p.avatar, radius: 16),
            title: Text(_name(t, p)),
            subtitle: Text(
              [
                for (final (i, s) in j.stages.indexed)
                  if (p.stages.contains(s.id)) '${i + 1}',
              ].join(' · '),
            ),
            trailing: j.canEdit ? const Icon(Icons.chevron_right) : null,
            onTap: j.canEdit && !_busy ? () => _edit(p) : null,
          ),
        if (j.isOwner)
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('people-who'),
                  controller: _who,
                  focusNode: widget.focus,
                  decoration: InputDecoration(labelText: t.peopleWho, isDense: true),
                  autocorrect: false,
                  keyboardType: TextInputType.emailAddress,
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(key: const Key('people-add'), onPressed: _busy ? null : _add, child: Text(t.peopleAdd)),
            ],
          ),
        if (_error case final e?) Text(e, style: TextStyle(color: theme.colorScheme.error)),
      ],
    );
  }
}
