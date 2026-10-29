import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import 'item_menu.dart';

/// Which items a list shows: all, the planned or the hiked ones.
enum DoneFilter { all, planned, done }

/// Whether an item hiked on [doneOn] (null: not hiked) passes [filter].
bool passesDone(DoneFilter filter, String? doneOn) => switch (filter) {
  DoneFilter.all => true,
  DoneFilter.planned => doneOn == null,
  DoneFilter.done => doneOn != null,
};

/// «Gewandert am 01.08.2026».
String doneText(AppLocalizations t, String doneOn) => t.doneOn(formatDate(DateTime.parse(doneOn)));

/// All, planned or hiked, above a list.
class DoneFilterBar extends StatelessWidget {
  const DoneFilterBar({super.key, required this.value, required this.onChanged});
  final DoneFilter value;
  final ValueChanged<DoneFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SegmentedButton<DoneFilter>(
        key: const Key('done-filter'),
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: DoneFilter.all, label: Text(t.doneFilterAll)),
          ButtonSegment(value: DoneFilter.planned, label: Text(t.doneFilterPlanned)),
          ButtonSegment(value: DoneFilter.done, label: Text(t.doneFilterDone)),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.single),
      ),
    );
  }
}

/// The menu's «Als gewandert markieren» (a day asked, today at first) and,
/// for one's own mark, «Nicht gewandert»; [onDone] gets the new state.
List<MenuAction> doneActions(
  BuildContext context,
  Api api, {
  required String id,
  required bool journey,
  required DoneState state,
  required ValueChanged<DoneState> onDone,
}) {
  final t = AppLocalizations.of(context);
  Future<void> set(bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    DateTime? day;
    if (on) {
      final today = DateUtils.dateOnly(DateTime.now());
      day = await showDatePicker(
        context: context,
        firstDate: DateTime(1990),
        lastDate: today,
        initialDate: state.doneOn != null ? DateTime.parse(state.doneOn!) : today,
      );
      if (day == null) return;
    }
    try {
      onDone(await api.setDone(id, journey: journey, on: on, day: day));
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    }
  }

  return [
    MenuAction('done', Icons.check_circle_outline, t.doneMark, () => set(true)),
    if (state.marked) MenuAction('undone', Icons.highlight_off, t.doneRemove, () => set(false)),
  ];
}

/// «Gewandert» on a list row: the state as an icon, [doneActions] behind it.
class DoneMenuButton extends StatelessWidget {
  const DoneMenuButton({
    super.key,
    required this.api,
    required this.id,
    required this.journey,
    required this.state,
    required this.onDone,
  });
  final Api api;
  final String id;
  final bool journey;
  final DoneState state;
  final ValueChanged<DoneState> onDone;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final on = state.doneOn;
    return PopupMenuButton<MenuAction>(
      tooltip: on == null ? t.doneMark : doneText(t, on),
      icon: Icon(
        on == null ? Icons.check_circle_outline : Icons.check_circle,
        color: on == null ? null : Theme.of(context).colorScheme.primary,
      ),
      itemBuilder: (context) => [
        for (final a in doneActions(context, api, id: id, journey: journey, state: state, onDone: onDone))
          PopupMenuItem(
            key: Key('done-${a.key}'),
            value: a,
            child: ListTile(leading: Icon(a.icon), title: Text(a.label), contentPadding: EdgeInsets.zero),
          ),
      ],
      onSelected: (a) => a.onTap(),
    );
  }
}
