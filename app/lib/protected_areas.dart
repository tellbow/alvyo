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
        Widget box(Key? key, bool now, String text) => Container(
          key: key,
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: now ? theme.colorScheme.tertiaryContainer : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(text, style: theme.textTheme.bodySmall),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (notices.isNotEmpty) ...[
              Text(key: const Key('notices'), t.noticesTitle, style: theme.textTheme.labelMedium),
              for (final n in notices)
                box(
                  null,
                  n.on(DateTime.now()) || days.any(n.on),
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
              const SizedBox(height: 8),
            ],
            if (list.isNotEmpty)
              Text(key: const Key('protected-areas'), t.areasTitle, style: theme.textTheme.labelMedium),
            for (final a in list)
              box(
                null,
                a.appliesOn(DateTime.now()) || days.any(a.appliesOn),
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
          ],
        );
      },
    );
  }
}
