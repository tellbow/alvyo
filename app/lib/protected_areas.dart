import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n/app_localizations.dart';

/// The protected areas along a route or journey, highlighted where their
/// rules apply today or on a planned day. Nothing while loading or offline.
class ProtectedAreas extends StatelessWidget {
  const ProtectedAreas(this.areas, {super.key, this.days = const []});

  final Future<List<ProtectedArea>> areas;

  /// Planned days of the hike.
  final List<DateTime> days;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final theme = Theme.of(context);
    return FutureBuilder(
      future: areas,
      builder: (context, snap) {
        final list = snap.data ?? const <ProtectedArea>[];
        if (list.isEmpty) return const SizedBox.shrink();
        String day(String mmdd) {
          final [m, d] = mmdd.split('-').map(int.parse).toList();
          return '$d.$m.';
        }

        return Column(
          key: const Key('protected-areas'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.areasTitle, style: theme.textTheme.labelMedium),
            for (final a in list)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: a.appliesOn(DateTime.now()) || days.any(a.appliesOn)
                      ? const Color(0xFFFFFBEB)
                      : theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  [
                    '${a.name} (${a.kind == 'wildlife_rest' ? t.areasWildlifeRest : t.areasHuntingReserve}, '
                        '${a.binding ? t.areasBinding : t.areasRecommended})',
                    [
                      a.ruleIn(lang),
                      if (a.period case final p?) t.areasPeriod(day(p.from), day(p.to)),
                      if (a.stages.isNotEmpty) t.areasStages(a.stages.join(', ')),
                    ].join(' · '),
                  ].join('\n'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        );
      },
    );
  }
}
