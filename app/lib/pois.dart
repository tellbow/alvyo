import 'package:flutter/material.dart';

import 'api.dart';
import 'format.dart';
import 'l10n/app_localizations.dart';
import 'place_layer.dart';
import 'poi_icons.dart';

/// Kinds that come many at once in a town (fountains, restaurants): listed together.
const _grouped = {'water', 'toilets', 'restaurant', 'picnic', 'firepit', 'shelter'};

/// A line of the list along a route: a point, or [count] of its kind up to [toM].
typedef PoiRow = ({Poi first, int count, double toM});

/// The points along a route as lines to list, as on the website: those of a
/// kind that comes many at once within [withinM] of the first of them
/// become one line; summits, viewpoints, waterfalls and cable cars stay one
/// each.
List<PoiRow> groupPois(List<Poi> pois, {double withinM = 1000}) {
  final rows = <PoiRow>[];
  final open = <String, int>{};
  for (final p in pois) {
    final i = open[p.kind];
    if (_grouped.contains(p.kind) && i != null && p.alongM - rows[i].first.alongM <= withinM) {
      rows[i] = (first: rows[i].first, count: rows[i].count + 1, toM: p.alongM);
      continue;
    }
    rows.add((first: p, count: 1, toM: p.alongM));
    if (_grouped.contains(p.kind)) open[p.kind] = rows.length - 1;
  }
  return rows;
}

/// What lies along a route (summits, water, fire places …), in the order they
/// come, a town's fountains and restaurants each on one line: the first ten
/// lines, the rest on request. Nothing while loading or offline.
class PoiList extends StatefulWidget {
  const PoiList(this.pois, {super.key});
  final Future<List<Poi>> pois;

  @override
  State<PoiList> createState() => _PoiListState();
}

class _PoiListState extends State<PoiList> {
  static const _first = 10;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return FutureBuilder(
      future: widget.pois,
      builder: (context, snap) {
        final rows = groupPois(snap.data ?? const <Poi>[]);
        if (rows.isEmpty) return const SizedBox.shrink();
        final shown = _all ? rows : rows.take(_first);
        return Column(
          key: const Key('pois'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text(t.poisTitle, style: theme.textTheme.labelMedium),
            for (final (:first, :count, :toM) in shown)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  spacing: 6,
                  children: [
                    PoiIcon(first.kind, size: 16),
                    Expanded(
                      child: Text(
                        count > 1
                            ? '${formatRange(first.alongM, toM)} · ${placeKindText(t, first.kind, '')} ×$count'
                            : [
                                formatDistance(first.alongM),
                                if (first.name.isNotEmpty) first.name,
                                placeKindText(t, first.kind, first.ele?.toString() ?? ''),
                              ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            if (!_all && rows.length > _first)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('pois-all'),
                  onPressed: () => setState(() => _all = true),
                  child: Text(t.poisAll(rows.length)),
                ),
              ),
          ],
        );
      },
    );
  }
}
