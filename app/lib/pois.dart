import 'package:flutter/material.dart';

import 'api.dart';
import 'format.dart';
import 'l10n/app_localizations.dart';
import 'place_layer.dart';
import 'poi_icons.dart';

/// What lies along a route (summits, water, fire places …), in the order they
/// come: the first ten, the rest on request. Nothing while loading or
/// offline.
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
        final pois = snap.data ?? const <Poi>[];
        if (pois.isEmpty) return const SizedBox.shrink();
        final shown = _all ? pois : pois.take(_first);
        return Column(
          key: const Key('pois'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text(t.poisTitle, style: theme.textTheme.labelMedium),
            for (final p in shown)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  spacing: 6,
                  children: [
                    PoiIcon(p.kind, size: 16),
                    Expanded(
                      child: Text(
                        [
                          formatDistance(p.alongM),
                          if (p.name.isNotEmpty) p.name,
                          placeKindText(t, p.kind, p.ele?.toString() ?? ''),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            if (!_all && pois.length > _first)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('pois-all'),
                  onPressed: () => setState(() => _all = true),
                  child: Text(t.poisAll(pois.length)),
                ),
              ),
          ],
        );
      },
    );
  }
}
