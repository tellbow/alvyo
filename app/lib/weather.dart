import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'format.dart';
import 'l10n/app_localizations.dart';

/// «4–13 °C · 3.2 mm Niederschlag (0.4–9.8 mm)», or «… · trocken», as on
/// the website.
String forecastText(AppLocalizations t, ForecastDay d, String language) {
  final n = NumberFormat('0.#', numberLocale(language));
  final temp = '${d.minC.round()}–${d.maxC.round()} °C';
  final rain = d.rainHiMm < 0.5
      ? t.weatherDry
      : t.weatherRain(n.format(d.rainMm), n.format(d.rainLoMm), n.format(d.rainHiMm));
  return '$temp · $rain';
}

/// A day (YYYY-MM-DD) as «Di., 29.9.».
String forecastDate(String date, String locale) => DateFormat.MEd(locale).format(DateTime.parse(date));

Widget _source(AppLocalizations t, ThemeData theme, DateTime run) => Padding(
  padding: const EdgeInsets.only(top: 4),
  child: Text(
    t.weatherSource('${formatDate(run)} ${formatTime(run)}'),
    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
  ),
);

/// MeteoSwiss's forecast at a route's start, highest point and end, for a
/// day chosen from the next ones. Nothing while loading or offline.
class RouteWeatherView extends StatefulWidget {
  const RouteWeatherView(this.weather, {super.key});
  final Future<RouteWeather?> weather;

  @override
  State<RouteWeatherView> createState() => _RouteWeatherViewState();
}

class _RouteWeatherViewState extends State<RouteWeatherView> {
  int _chosen = 0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    String role(String r) => switch (r) {
      'start' => t.weatherStart,
      'top' => t.weatherTop,
      _ => t.weatherEnd,
    };
    return FutureBuilder(
      future: widget.weather,
      builder: (context, snap) {
        final w = snap.data;
        final dates = [for (final d in w?.places.firstOrNull?.days ?? const <ForecastDay>[]) d.date];
        if (w == null || dates.isEmpty) return const SizedBox.shrink();
        final chosen = _chosen.clamp(0, dates.length - 1);
        return Column(
          key: const Key('weather'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text(t.weatherTitle, style: theme.textTheme.labelMedium),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final (i, date) in dates.indexed)
                  ChoiceChip(
                    label: Text(i == 0 ? t.weatherToday : forecastDate(date, locale)),
                    selected: i == chosen,
                    onSelected: (_) => setState(() => _chosen = i),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            for (final p in w.places)
              if (p.days.where((d) => d.date == dates[chosen]).firstOrNull case final day?)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${p.roles.map(role).join(', ')} · ${p.point.name}, ${formatHeight(p.point.height)}\n'
                    '${forecastText(t, day, locale)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            _source(t, theme, w.run),
          ],
        );
      },
    );
  }
}

/// The forecast at each stage's highest point for its planned day, for the
/// stages planned within the forecast. Nothing while loading or offline.
class JourneyWeatherView extends StatelessWidget {
  const JourneyWeatherView(this.weather, {super.key});
  final Future<JourneyWeather?> weather;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    return FutureBuilder(
      future: weather,
      builder: (context, snap) {
        final w = snap.data;
        final planned = [
          for (final s in w?.stages ?? const <({int stage, ForecastPoint point, ForecastDay? day})>[])
            if (s.day case final day?) (s, day),
        ];
        if (w == null || planned.isEmpty) return const SizedBox.shrink();
        return Column(
          key: const Key('weather'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text(t.weatherTitle, style: theme.textTheme.labelMedium),
            for (final (s, day) in planned)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${t.weatherStage(s.stage, forecastDate(day.date, locale))} · '
                  '${s.point.name}, ${formatHeight(s.point.height)}\n'
                  '${forecastText(t, day, locale)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            _source(t, theme, w.run),
          ],
        );
      },
    );
  }
}
