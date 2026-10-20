import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'format.dart';
import 'l10n/app_localizations.dart';

/// Shows parts of the route (lines of [lon, lat]) on the map.
typedef ShowParts = void Function(List<List<List<double>>> parts);

/// The closed trails, army shooting and protected areas along a route or
/// journey, highlighted where they concern today or a planned day. Nothing
/// while loading or offline.
class ProtectedAreas extends StatelessWidget {
  const ProtectedAreas(this.along, {super.key, this.days = const [], this.onShow});

  final Future<Along> along;

  /// Planned days of the hike.
  final List<DateTime> days;

  /// Shows where the line is concerned on the map; no button without.
  final ShowParts? onShow;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
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
        Widget box(Key? key, String? when, String text, List<List<List<double>>> where) =>
            _box(context, key, when != null, when == null ? text : '$text\n$when', where, onShow);

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
              n.where,
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
              a.where,
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

/// An entry of a list in a sheet, highlighted when it concerns the hike;
/// with [where] and [onShow] a button closes the sheet and shows it on the
/// map.
Widget _box(
  BuildContext context,
  Key? key,
  bool highlight,
  String text,
  List<List<List<double>>> where,
  ShowParts? onShow,
) {
  final t = AppLocalizations.of(context);
  final theme = Theme.of(context);
  return Container(
    key: key,
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: highlight ? theme.colorScheme.tertiaryContainer : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: theme.textTheme.bodySmall),
        if (onShow != null && where.isNotEmpty)
          // Built in the sheet: its context closes the sheet.
          Builder(
            builder: (sheet) => TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
              onPressed: () {
                Navigator.of(sheet).pop();
                onShow(where);
              },
              child: Text(t.showOnMap),
            ),
          ),
      ],
    ),
  );
}

/// The snow along a route or journey: how much, how much of it steep, the
/// stretches in a sheet. Nothing while loading, offline or without snow.
class SnowAlongView extends StatelessWidget {
  const SnowAlongView(this.snow, {super.key, this.onShow});

  final Future<SnowAlong?> snow;

  /// Shows a stretch on the map.
  final ShowParts? onShow;

  /// A length in snow to the nearest 50 m: the data's pixels are 60 m.
  static String roughly(double metres) => formatDistance(max(50, (metres / 50).round() * 50).toDouble());

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return FutureBuilder(
      future: snow,
      builder: (context, snap) {
        final s = snap.data;
        final date = s?.date;
        if (s == null || date == null || (s.snowM == 0 && s.patchesM == 0)) return const SizedBox.shrink();
        final day = DateFormat.MMMMd(locale).format(DateTime.parse(date));
        final credit = Text(s.attribution, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor));
        if (s.snowM == 0) {
          return Padding(
            key: const Key('snow-along'),
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.snowAlongTitle, style: theme.textTheme.labelMedium),
                Text(t.snowAlongPatchesOnly(roughly(s.patchesM), day), style: theme.textTheme.bodySmall),
                credit,
              ],
            ),
          );
        }
        final steep = s.slopes && s.steepM > 0;
        return _HintLine(
          key: const Key('snow-along'),
          title: t.snowAlongTitle,
          count: s.stretches.length,
          note: steep ? t.snowAlongNoteSteep(roughly(s.snowM), roughly(s.steepM)) : t.snowAlongNote(roughly(s.snowM)),
          children: [
            Text(
              [
                steep
                    ? t.snowAlongSummarySteep(roughly(s.snowM), roughly(s.steepM))
                    : t.snowAlongSummary(roughly(s.snowM)),
                if (s.patchesM > 0) t.snowAlongPatches(roughly(s.patchesM)),
              ].join(' '),
            ),
            for (final st in s.stretches)
              _box(
                context,
                null,
                s.slopes && st.steepM > 0,
                [
                  if (st.stage case final n?) t.areasStages('$n'),
                  t.snowAlongStretch(formatDistance(st.fromM), roughly(st.toM - st.fromM)),
                  if (s.slopes && st.steepM > 0) t.snowAlongStretchSteep(roughly(st.steepM)),
                ].join(' · '),
                [st.line],
                onShow,
              ),
            const SizedBox(height: 8),
            Text('${t.snowDate(day)}. ${t.snowAlongLimits}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(t.snowHint, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            credit,
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
