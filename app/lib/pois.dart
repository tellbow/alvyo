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
/// come, a town's fountains and restaurants each on one line; chips above
/// show one kind only. Nothing while loading or offline.
class PoiList extends StatefulWidget {
  const PoiList(this.pois, {super.key, this.onTap});
  final Future<List<Poi>> pois;

  /// Given the points of a line tapped (one, or those it groups), e.g. to
  /// show them on the map.
  final ValueChanged<List<Poi>>? onTap;

  @override
  State<PoiList> createState() => _PoiListState();
}

class _PoiListState extends State<PoiList> {
  /// The kind shown alone; null for all.
  String? _only;

  /// The line tapped last, by its first point.
  Poi? _tapped;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return FutureBuilder(
      future: widget.pois,
      builder: (context, snap) {
        final pois = snap.data ?? const <Poi>[];
        if (pois.isEmpty) return const SizedBox.shrink();
        final counts = <String, int>{};
        for (final p in pois) {
          counts[p.kind] = (counts[p.kind] ?? 0) + 1;
        }
        final rows = groupPois(
          _only == null
              ? pois
              : [
                  for (final p in pois)
                    if (p.kind == _only) p,
                ],
        );
        return Column(
          key: const Key('pois'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (counts.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text(t.poisFilterAll(pois.length)),
                      selected: _only == null,
                      onSelected: (_) => setState(() {
                        _only = null;
                        _tapped = null;
                      }),
                      visualDensity: VisualDensity.compact,
                    ),
                    for (final MapEntry(key: kind, value: n) in counts.entries)
                      ChoiceChip(
                        key: Key('pois-$kind'),
                        avatar: PoiIcon(kind, size: 16),
                        label: Text('${placeKindText(t, kind, '')} $n'),
                        selected: _only == kind,
                        onSelected: (_) => setState(() {
                          _only = kind;
                          _tapped = null;
                        }),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            for (final (i, (:first, :count, :toM)) in rows.indexed)
              InkWell(
                key: Key('poi-$i'),
                onTap: widget.onTap == null
                    ? null
                    : () {
                        setState(() => _tapped = first);
                        widget.onTap!([
                          for (final p in pois)
                            if (p.kind == first.kind && p.alongM >= first.alongM && p.alongM <= toM) p,
                        ]);
                      },
                child: Container(
                  color: identical(_tapped, first) ? theme.colorScheme.secondaryContainer : null,
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  // Rows to tap while walking: as tall as a finger needs.
                  constraints: BoxConstraints(minHeight: widget.onTap == null ? 0 : 44),
                  alignment: Alignment.centerLeft,
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
              ),
          ],
        );
      },
    );
  }
}
