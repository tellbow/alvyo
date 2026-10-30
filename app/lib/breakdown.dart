import 'package:flutter/material.dart';

import 'format.dart';
import 'l10n/app_localizations.dart';
import 'trail_mark.dart';

/// A share of a route's metres of one kind (surface, way type, trail).
typedef BreakdownPart = ({String key, double metres, double share});

/// The shares to show, in the order of [keys]; none when nothing but
/// [unknown] is known (a grey bar says nothing). As on the website.
List<BreakdownPart> breakdownParts(Map<String, double> values, List<String> keys, {String? unknown}) {
  final total = keys.fold(0.0, (a, k) => a + (values[k] ?? 0));
  if (total <= (unknown == null ? 0 : values[unknown] ?? 0)) return const [];
  return [
    for (final k in keys)
      if ((values[k] ?? 0) > 0) (key: k, metres: values[k]!, share: values[k]! / total),
  ];
}

/// A legend's lines: the [n] largest parts, the share of the rest as other.
({List<BreakdownPart> top, double other}) legendParts(List<BreakdownPart> parts, {int n = 3}) {
  final sorted = [...parts]..sort((a, b) => b.share.compareTo(a.share));
  return (top: sorted.take(n).toList(), other: sorted.skip(n).fold(0.0, (a, p) => a + p.share));
}

/// The metres per key of a field of the legs (trails, surfaces, way_types)
/// of a route as the server sent it.
Map<String, double> sumLegs(Map<String, dynamic> route, String field) {
  final out = <String, double>{};
  for (final leg in route['legs'] as List? ?? const []) {
    final values = (leg as Map<String, dynamic>)[field];
    if (values is! Map) continue;
    for (final MapEntry(:key, :value) in values.entries) {
      out[key as String] = (out[key] ?? 0) + (value as num).toDouble();
    }
  }
  return out;
}

/// The colours of the website (web/src/lib/planner/colors.ts).
const _trailColors = {
  'Wanderweg': Color(0xffeab308),
  'Bergwanderweg': Color(0xffdc2626),
  'Alpinwanderweg': Color(0xff2563eb),
  'none': Color(0xffa8a29e),
};
const _surfaceColors = {
  'paved': Color(0xff57534e),
  'gravel': Color(0xffa8a29e),
  'natural': Color(0xff65a30d),
  'unknown': Color(0xffe7e5e4),
};
const _wayColors = {
  'road': Color(0xff57534e),
  'track': Color(0xffa16207),
  'path': Color(0xff65a30d),
  'steps': Color(0xff7c3aed),
  'unknown': Color(0xffe7e5e4),
};

/// Whether the whole route runs off marked hiking trails.
bool offTrail(Map<String, dynamic> route) {
  final parts = breakdownParts(sumLegs(route, 'trails'), _trailColors.keys.toList());
  return parts.length == 1 && parts.single.key == 'none';
}

/// «Kein offizieller Wanderweg»: said in words, not as a bar of one colour.
class OffTrailWarning extends StatelessWidget {
  const OffTrailWarning({super.key, required this.distanceM});
  final double distanceM;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      key: const Key('off-trail'),
      color: theme.colorScheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.onErrorContainer),
        title: Text(t.offTrailTitle, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
        subtitle: Text(
          t.offTrailAll(formatDistance(distanceM)),
          style: TextStyle(color: theme.colorScheme.onErrorContainer),
        ),
      ),
    );
  }
}

/// «Wegbeschaffenheit»: the route's trail network, surfaces and kinds of way,
/// a bar only where there is more than one kind, the three largest in per
/// cent, the kilometres behind «Details». Nothing without legs.
class TrailConditions extends StatelessWidget {
  const TrailConditions({super.key, required this.route, required this.distanceM});
  final Map<String, dynamic> route;
  final double distanceM;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final bars = [
      (
        title: t.breakdownTrail,
        colors: _trailColors,
        labels: {
          'Wanderweg': t.trailWanderweg,
          'Bergwanderweg': t.trailBergwanderweg,
          'Alpinwanderweg': t.trailAlpinwanderweg,
          'none': t.trailNone,
        },
        parts: breakdownParts(sumLegs(route, 'trails'), _trailColors.keys.toList()),
      ),
      (
        title: t.breakdownSurface,
        colors: _surfaceColors,
        labels: {
          'paved': t.surfacePaved,
          'gravel': t.surfaceGravel,
          'natural': t.surfaceNatural,
          'unknown': t.surfaceUnknown,
        },
        parts: breakdownParts(sumLegs(route, 'surfaces'), _surfaceColors.keys.toList(), unknown: 'unknown'),
      ),
      (
        title: t.breakdownWay,
        colors: _wayColors,
        labels: {
          'road': t.wayRoad,
          'track': t.wayTrack,
          'path': t.wayPath,
          'steps': t.waySteps,
          'unknown': t.wayUnknown,
        },
        parts: breakdownParts(sumLegs(route, 'way_types'), _wayColors.keys.toList(), unknown: 'unknown'),
      ),
    ];
    if (bars.every((b) => b.parts.isEmpty)) return const SizedBox.shrink();
    String percent(double s) => s < 0.005 ? '<1 %' : '${(s * 100).round()} %';
    return Card(
      key: const Key('trail-conditions'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(t.breakdownTitle, style: theme.textTheme.labelLarge)),
                Text(formatDistance(distanceM), style: muted),
              ],
            ),
            for (final b in bars)
              if (b.parts.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(b.title, style: muted),
                // One kind alone is no distribution: the legend says it.
                if (b.parts.length > 1) ...[
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 8,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final p in b.parts)
                            Expanded(
                              flex: (p.share * 1000).round().clamp(1, 1000),
                              child: ColoredBox(color: b.colors[p.key]!),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  children: [
                    for (final p in legendParts(b.parts).top)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 4,
                        children: [
                          // The official trails' markings (feedback issue 71).
                          if (identical(b.colors, _trailColors) && p.key != 'none')
                            TrailMark(p.key)
                          else
                            Icon(Icons.circle, size: 8, color: b.colors[p.key]),
                          Text('${b.labels[p.key] ?? p.key} ${percent(p.share)}', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    if (legendParts(b.parts).other > 0)
                      Text(
                        '${t.breakdownOther} ${percent(legendParts(b.parts).other)}',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ],
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const Key('trail-details'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                title: Text(t.breakdownDetails, style: muted),
                children: [
                  Text(
                    [
                      for (final b in bars)
                        for (final p in b.parts) '${b.labels[p.key] ?? p.key} ${formatDistance(p.metres)}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
