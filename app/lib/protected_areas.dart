import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n/app_localizations.dart';

/// The closed trails, army shooting and protected areas along a route or
/// journey, highlighted where they concern today or a planned day. Nothing
/// while loading or offline.
class ProtectedAreas extends StatelessWidget {
  const ProtectedAreas(this.along, {super.key, this.days = const []});

  final Future<Along> along;

  /// Planned days of the hike.
  final List<DateTime> days;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final theme = Theme.of(context);
    return FutureBuilder(
      future: along,
      builder: (context, snap) {
        final list = snap.data?.areas ?? const <ProtectedArea>[];
        final notices = snap.data?.notices ?? const <Notice>[];
        String day(String mmdd) {
          final [m, d] = mmdd.split('-').map(int.parse).toList();
          return '$d.$m.';
        }

        String date(String iso) => day(iso.substring(5));
        String hour(String hhmm) => '${hhmm.substring(0, 2)}:${hhmm.substring(2)}';
        // What applies now, else on a planned day, is said beside the count.
        String? note(bool Function(DateTime) on) =>
            on(DateTime.now()) ? t.areasNow : (days.any(on) ? t.areasOnDate : null);
        // When it applies in words too, not only by the box's colour.
        Widget box(Key? key, String? when, String text) => Container(
          key: key,
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: when != null ? theme.colorScheme.tertiaryContainer : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(when == null ? text : '$text\n$when', style: theme.textTheme.bodySmall),
        );

        final noticeBoxes = [
          for (final n in notices)
            box(
              null,
              note(n.on),
              [
                '${n.titleIn(lang)} (${n.kind == 'closure' ? t.noticesClosure : t.noticesShooting})',
                [
                  if (n.reasonIn(lang).isNotEmpty) n.reasonIn(lang),
                  if ((n.from, n.to) case (final f?, final u?)) '${date(f)}–${date(u)}',
                  if (n.days.isNotEmpty)
                    n.days
                        .map(
                          (d) => d.from.length == 4 && d.to.length == 4
                              ? '${date(d.date)} ${hour(d.from)}–${hour(d.to)}'
                              : date(d.date),
                        )
                        .join(', '),
                  if (n.phone.isNotEmpty) n.phone,
                  if (n.stages.isNotEmpty) t.areasStages(n.stages.join(', ')),
                ].join(' · '),
              ].join('\n'),
            ),
        ];
        final areaBoxes = [
          for (final a in list)
            box(
              null,
              note(a.appliesOn),
              [
                '${a.name} (${a.kind == 'wildlife_rest' ? t.areasWildlifeRest : t.areasHuntingReserve}, '
                    '${a.binding ? t.areasBinding : t.areasRecommended})',
                [
                  a.ruleIn(lang),
                  if (a.period case final p?) t.areasPeriod(day(p.from), day(p.to)),
                  if (a.stages.isNotEmpty) t.areasStages(a.stages.join(', ')),
                ].join(' · '),
              ].join('\n'),
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (notices.isNotEmpty)
              _HintLine(
                key: const Key('notices'),
                title: t.noticesTitle,
                count: notices.length,
                note: note((d) => notices.any((n) => n.on(d))),
                children: noticeBoxes,
              ),
            if (list.isNotEmpty)
              _HintLine(
                key: const Key('protected-areas'),
                title: t.areasTitle,
                count: list.length,
                note: note((d) => list.any((a) => a.appliesOn(d))),
                children: areaBoxes,
              ),
          ],
        );
      },
    );
  }
}

/// A line with how many there are; the list itself in a sheet, on request.
class _HintLine extends StatelessWidget {
  const _HintLine({super.key, required this.title, required this.count, this.note, required this.children});
  final String title;
  final int count;
  final String? note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: note != null ? theme.colorScheme.tertiaryContainer : null,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (context) => DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.6,
                maxChildSize: 0.9,
                builder: (context, scroll) => SafeArea(
                  child: ListView(
                    controller: scroll,
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      ...children,
                    ],
                  ),
                ),
              ),
            ),
            child: Text(note == null ? t.hintsOpen(count) : '${t.hintsOpen(count)} · $note'),
          ),
        ],
      ),
    );
  }
}
