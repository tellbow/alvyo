import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:maplibre/maplibre.dart';

import 'api.dart';
import 'l10n/app_localizations.dart';

/// One picture of the rain timeline.
class PrecipFrame {
  PrecipFrame.fromJson(Map<String, dynamic> j)
    : kind = j['kind'] as String,
      time = DateTime.parse(j['time'] as String),
      url = j['url'] as String;

  /// radar (measured) or forecast (the hour ending at [time]).
  final String kind;
  final DateTime time;
  final String url;
}

/// The rain on the map (`GET /weather/precip`): MeteoSwiss's radar of the
/// last hour, then the forecast, as pictures over [west]…[north].
class PrecipTimeline {
  PrecipTimeline.fromJson(Map<String, dynamic> j)
    : frames = [for (final f in j['frames'] as List) PrecipFrame.fromJson(f as Map<String, dynamic>)],
      legend = [
        for (final l in j['legend'] as List)
          Color(0xff000000 | int.parse(((l as Map<String, dynamic>)['color'] as String).substring(1), radix: 16)),
      ],
      attribution = j['attribution'] as String,
      west = ((j['bounds'] as Map<String, dynamic>)['west'] as num).toDouble(),
      south = ((j['bounds'] as Map<String, dynamic>)['south'] as num).toDouble(),
      east = ((j['bounds'] as Map<String, dynamic>)['east'] as num).toDouble(),
      north = ((j['bounds'] as Map<String, dynamic>)['north'] as num).toDouble();

  final List<PrecipFrame> frames;
  final List<Color> legend;
  final String attribution;
  final double west, south, east, north;

  /// Where the timeline starts: the newest radar picture.
  int get now => frames.lastIndexWhere((f) => f.kind == 'radar').clamp(0, frames.length);
}

/// Shows the rain on a map while the overlay «precip» is on: one picture at
/// a time below the places, refreshed every 5 minutes. The image sources
/// stay; only the layer moves from one to the next (the iOS plugin cannot
/// change an image source's picture).
class PrecipController {
  PrecipController(this.api, this.overlays) {
    overlays.addListener(_sync);
    index.addListener(_show);
  }

  final Api api;
  final ValueListenable<Set<String>> overlays;
  final timeline = ValueNotifier<PrecipTimeline?>(null);
  final index = ValueNotifier<int>(0);
  final playing = ValueNotifier<bool>(false);

  static const _layer = 'precip';
  StyleController? _style;
  String? _below;
  Timer? _refresh, _play;
  final _sources = <String>{};
  String? _shown;
  Future<void> _done = Future.value();

  bool get on => overlays.value.contains('precip');

  /// Draws below [below] on a map whose style just loaded.
  void attach(StyleController style, {required String below}) {
    _style = style;
    _below = below;
    _sources.clear();
    _shown = null;
    _sync();
  }

  void dispose() {
    overlays.removeListener(_sync);
    index.removeListener(_show);
    _refresh?.cancel();
    _play?.cancel();
    _style = null;
  }

  void play(bool on) {
    playing.value = on;
    _play?.cancel();
    final n = timeline.value?.frames.length ?? 0;
    if (on && n > 1) {
      _play = Timer.periodic(const Duration(milliseconds: 700), (_) => index.value = (index.value + 1) % n);
    }
  }

  void _sync() {
    if (!on) {
      _refresh?.cancel();
      _refresh = null;
      play(false);
      _clear();
      return;
    }
    if (_refresh == null) {
      _refresh = Timer.periodic(const Duration(minutes: 5), (_) => _load());
      _load();
    } else {
      _show();
    }
  }

  /// Fetches the timeline, keeping the time shown; without a connection the
  /// last one stays.
  Future<void> _load() async {
    try {
      final next = await api.precip();
      final shown = switch (timeline.value) {
        final t? when index.value < t.frames.length => t.frames[index.value].time,
        _ => null,
      };
      timeline.value = next;
      final same = next.frames.indexWhere((f) => f.time == shown);
      final i = same >= 0 ? same : next.now;
      if (index.value == i) {
        _show();
      } else {
        index.value = i;
      }
    } on Object {
      // offline: the pictures shown so far stay
    }
  }

  void _show() {
    _done = _done.then((_) async {
      final style = _style, t = timeline.value;
      if (style == null || t == null || !on || index.value >= t.frames.length) return;
      final f = t.frames[index.value];
      final id = 'precip-${f.url.hashCode}';
      if (_shown == id) return;
      try {
        if (!_sources.contains(id)) {
          await style.addSource(
            ImageSource(
              id: id,
              url: '${api.server}${f.url}',
              coordinates: LngLatQuad(
                topLeft: Geographic(lon: t.west, lat: t.north),
                topRight: Geographic(lon: t.east, lat: t.north),
                bottomRight: Geographic(lon: t.east, lat: t.south),
                bottomLeft: Geographic(lon: t.west, lat: t.south),
              ),
            ),
          );
          _sources.add(id);
        }
        if (_shown != null) await style.removeLayer(_layer);
        await style.addLayer(
          RasterStyleLayer(id: _layer, sourceId: id, paint: const {'raster-opacity': 0.8, 'raster-fade-duration': 0}),
          belowLayerId: _below,
        );
        _shown = id;
        // Pictures that left the timeline.
        final wanted = {for (final f in t.frames) 'precip-${f.url.hashCode}'};
        for (final old in _sources.where((s) => !wanted.contains(s)).toList()) {
          await style.removeSource(old);
          _sources.remove(old);
        }
      } on Object {
        // the map went away meanwhile
      }
    });
  }

  void _clear() {
    _done = _done.then((_) async {
      final style = _style;
      if (style == null) return;
      try {
        if (_shown != null) await style.removeLayer(_layer);
        for (final s in _sources) {
          await style.removeSource(s);
        }
      } on Object {
        // the map went away meanwhile
      }
      _shown = null;
      _sources.clear();
    });
  }
}

/// «09:45», a forecast hour «09:00–10:00»; with the weekday when not today.
String precipTime(PrecipFrame f, String locale, {DateTime? now}) {
  final end = f.time.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final day = end.year == today.year && end.month == today.month && end.day == today.day
      ? ''
      : '${DateFormat.E(locale).format(end)} ';
  final hm = DateFormat.Hm(locale);
  if (f.kind == 'radar') return '$day${hm.format(end)}';
  return '$day${hm.format(end.subtract(const Duration(hours: 1)))}–${hm.format(end)}';
}

/// The timeline over a map with the rain on: play, a slider, the time and
/// whether measured or forecast, and the legend. Nothing while it is off.
class PrecipBar extends StatelessWidget {
  const PrecipBar({super.key, required this.controller});
  final PrecipController controller;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([controller.overlays, controller.timeline, controller.index, controller.playing]),
      builder: (context, _) {
        if (!controller.on) return const SizedBox.shrink();
        final tl = controller.timeline.value;
        final small = theme.textTheme.bodySmall;
        final card = Card(
          key: const Key('precip'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 12, 8),
            child: switch (tl) {
              null => const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
              _ when tl.frames.isEmpty => Padding(padding: const EdgeInsets.all(8), child: Text(t.precipNone)),
              _ => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        key: const Key('precip-play'),
                        visualDensity: VisualDensity.compact,
                        tooltip: controller.playing.value ? t.precipPause : t.precipPlay,
                        icon: Icon(controller.playing.value ? Icons.pause : Icons.play_arrow),
                        onPressed: () => controller.play(!controller.playing.value),
                      ),
                      Expanded(
                        child: Slider(
                          key: const Key('precip-slider'),
                          value: controller.index.value.clamp(0, tl.frames.length - 1).toDouble(),
                          max: (tl.frames.length - 1).toDouble(),
                          divisions: tl.frames.length > 1 ? tl.frames.length - 1 : null,
                          // VoiceOver reads the time, not a percentage.
                          semanticFormatterCallback: (v) => precipTime(tl.frames[v.round()], locale),
                          onChanged: (v) {
                            controller.play(false);
                            controller.index.value = v.round();
                          },
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(
                      children: [
                        Text(
                          precipTime(tl.frames[controller.index.value.clamp(0, tl.frames.length - 1)], locale),
                          key: const Key('precip-time'),
                          style: small?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Text(
                          tl.frames[controller.index.value.clamp(0, tl.frames.length - 1)].kind == 'radar'
                              ? t.precipRadar
                              : t.precipForecast,
                          key: const Key('precip-kind'),
                          style: small,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 0, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        height: 6,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [for (final c in tl.legend) Expanded(child: ColoredBox(color: c))],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(t.precipLight, style: small),
                        Text('© ${tl.attribution}', style: small),
                        Text(t.precipHeavy, style: small),
                      ],
                    ),
                  ),
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
