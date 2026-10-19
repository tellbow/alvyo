import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:maplibre/maplibre.dart';

import 'api.dart';
import 'l10n/app_localizations.dart';

/// The snow cover on the map (`GET /weather/snow`): Copernicus's daily
/// snow cover as tiles; no [date] while there is none.
class SnowCover {
  SnowCover.fromJson(Map<String, dynamic> j)
    : date = j['date'] == null ? null : DateTime.parse(j['date'] as String),
      tiles = j['tiles'] as String?,
      minZoom = (j['minzoom'] as num).toDouble(),
      maxZoom = (j['maxzoom'] as num).toDouble(),
      legend = [
        for (final l in j['legend'] as List)
          Color(0xff000000 | int.parse(((l as Map<String, dynamic>)['color'] as String).substring(1), radix: 16)),
      ],
      attribution = j['attribution'] as String;

  final DateTime? date;
  final String? tiles;
  final double minZoom, maxZoom;
  final List<Color> legend;
  final String attribution;
}

/// Shows the snow cover on a map while the overlay «snow» is on, below the
/// places; the day is looked for again every hour.
class SnowController {
  SnowController(this.api, this.overlays) {
    overlays.addListener(_sync);
  }

  final Api api;
  final ValueListenable<Set<String>> overlays;
  final cover = ValueNotifier<SnowCover?>(null);

  static const _id = 'snow';
  StyleController? _style;
  String? _below;
  Timer? _refresh;
  String? _shown; // the tiles' URL on the map
  Future<void> _done = Future.value();

  bool get on => overlays.value.contains('snow');

  /// Draws below [below] on a map whose style just loaded.
  void attach(StyleController style, {required String below}) {
    _style = style;
    _below = below;
    _shown = null;
    _sync();
  }

  void dispose() {
    overlays.removeListener(_sync);
    _refresh?.cancel();
    _style = null;
  }

  void _sync() {
    if (!on) {
      _refresh?.cancel();
      _refresh = null;
      _clear();
      return;
    }
    if (_refresh == null) {
      _refresh = Timer.periodic(const Duration(hours: 1), (_) => _load());
      _load();
    } else {
      _show();
    }
  }

  /// Without a connection the day shown so far stays.
  Future<void> _load() async {
    try {
      cover.value = await api.snow();
      _show();
    } on Object {
      // offline
    }
  }

  void _show() {
    _done = _done.then((_) async {
      final style = _style, c = cover.value;
      final tiles = c?.tiles;
      if (style == null || c == null || tiles == null || !on || _shown == tiles) return;
      try {
        if (_shown != null) {
          await style.removeLayer(_id);
          await style.removeSource(_id);
        }
        await style.addSource(
          RasterSource(
            id: _id,
            tiles: ['${api.server}$tiles'],
            tileSize: 256,
            minZoom: c.minZoom,
            maxZoom: c.maxZoom,
            attribution: c.attribution,
          ),
        );
        await style.addLayer(
          RasterStyleLayer(id: _id, sourceId: _id),
          belowLayerId: _below,
        );
        _shown = tiles;
      } on Object {
        // the map went away meanwhile
      }
    });
  }

  void _clear() {
    _done = _done.then((_) async {
      final style = _style;
      if (style == null || _shown == null) return;
      try {
        await style.removeLayer(_id);
        await style.removeSource(_id);
      } on Object {
        // the map went away meanwhile
      }
      _shown = null;
    });
  }
}

/// The snow cover's day and legend over a map with it on; nothing while
/// it is off.
class SnowBar extends StatelessWidget {
  const SnowBar({super.key, required this.controller});
  final SnowController controller;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final small = Theme.of(context).textTheme.bodySmall;
    return ListenableBuilder(
      listenable: Listenable.merge([controller.overlays, controller.cover]),
      builder: (context, _) {
        if (!controller.on) return const SizedBox.shrink();
        final c = controller.cover.value;
        final card = Card(
          key: const Key('snow'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: switch (c) {
              null => const LinearProgressIndicator(),
              SnowCover(date: null) => Text(t.snowNone),
              SnowCover(:final date?) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t.snowDate(DateFormat.MMMMd(locale).format(date)),
                    key: const Key('snow-date'),
                    style: small?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  // Each colour with its name: 15, 50 and 90 % snow.
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        for (final (i, l) in c.legend.indexed)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 2),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: SizedBox(height: 6, child: ColoredBox(color: l)),
                                  ),
                                  Text([t.snowPatchy, t.snowMostly, t.snowFull].elementAtOrNull(i) ?? '', style: small),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(t.snowHint, style: small),
                  ),
                  Text('${t.snowNote} · Copernicus (EU)', style: small),
                ],
              ),
            },
          ),
        );
        return Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: card),
        );
      },
    );
  }
}
