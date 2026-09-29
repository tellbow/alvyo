import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'format.dart';
import 'l10n/app_localizations.dart';
import 'weather_symbols.dart';

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

/// «Üblich im Oktober: 3–11 °C, an 10 von 31 Tagen Regen, 102 mm im Monat».
String climateText(AppLocalizations t, Climate c, int year, String language) {
  final n = NumberFormat('0', numberLocale(language));
  return t.weatherClimate(
    DateFormat.MMMM(language).format(DateTime(year, c.month)),
    n.format(c.minC.round()),
    n.format(c.maxC.round()),
    n.format(c.rainDays.round()),
    '${DateUtils.getDaysInMonth(year, c.month)}',
    n.format(c.rainMm.round()),
  );
}

/// A day (YYYY-MM-DD) as «Di., 29.9.».
String forecastDate(String date, String locale) => DateFormat.MEd(locale).format(DateTime.parse(date));

/// A day's weather: MeteoSwiss's symbol beside the words.
Widget _line(ThemeData theme, Widget? icon, String text) => Padding(
  padding: const EdgeInsets.only(top: 4),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 6,
    children: [
      ?icon,
      Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
    ],
  ),
);

Widget _climateSource(AppLocalizations t, ThemeData theme, Climate c) => Padding(
  padding: const EdgeInsets.only(top: 4),
  child: Text(
    key: const Key('weather-climate-source'),
    t.weatherClimateSource(c.station, c.rainStation),
    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
  ),
);

Widget _source(AppLocalizations t, ThemeData theme, DateTime run) => Padding(
  padding: const EdgeInsets.only(top: 4),
  child: Text(
    t.weatherSource('${formatDate(run)} ${formatTime(run)}'),
    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
  ),
);

/// MeteoSwiss's forecast at a route's start, highest point and end, for a
/// day chosen from the next ones; any later day, loaded by [later], has
/// what is usual in its month. Nothing while loading or offline.
class RouteWeatherView extends StatefulWidget {
  const RouteWeatherView(this.weather, {super.key, this.later});
  final Future<RouteWeather?> weather;
  final Future<RouteWeather?> Function(String date)? later;

  @override
  State<RouteWeatherView> createState() => _RouteWeatherViewState();
}

class _RouteWeatherViewState extends State<RouteWeatherView> {
  int _chosen = 0;

  /// A day beyond the forecast, and its answer.
  (String, Future<RouteWeather?>)? _later;

  Future<void> _pickLater(List<String> dates) async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      initialDate: now.add(const Duration(days: 10)),
    );
    if (day == null || !mounted) return;
    final date = DateFormat('yyyy-MM-dd').format(day);
    setState(() {
      if (dates.indexOf(date) case final i when i >= 0) {
        _chosen = i;
        _later = null;
      } else {
        _later = (date, widget.later!(date));
      }
    });
  }

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
        final later = _later;
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
                    selected: later == null && i == chosen,
                    onSelected: (_) => setState(() {
                      _chosen = i;
                      _later = null;
                    }),
                    visualDensity: VisualDensity.compact,
                  ),
                if (widget.later != null)
                  ChoiceChip(
                    key: const Key('weather-date'),
                    avatar: const Icon(Icons.calendar_month, size: 16),
                    label: Text(later == null ? t.weatherOtherDay : formatDate(DateTime.parse(later.$1))),
                    selected: later != null,
                    onSelected: (_) => _pickLater(dates),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (later == null) ...[
              for (final p in w.places)
                if (p.days.where((d) => d.date == dates[chosen]).firstOrNull case final day?)
                  _line(
                    theme,
                    WeatherIcon(day.symbol),
                    '${p.roles.map(role).join(', ')} · ${p.point.name}, ${formatHeight(p.point.height)}\n'
                    '${forecastText(t, day, locale)}',
                  ),
              _source(t, theme, w.run),
            ] else
              FutureBuilder(
                future: later.$2,
                builder: (context, snap) {
                  final places = [
                    for (final p in snap.data?.places ?? const <Never>[])
                      if (p.climate case final c?) (p, c),
                  ];
                  if (places.isEmpty) return const SizedBox.shrink();
                  final year = int.parse(later.$1.substring(0, 4));
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (p, c) in places)
                        _line(
                          theme,
                          null,
                          '${p.roles.map(role).join(', ')} · ${p.point.name}, ${formatHeight(p.point.height)}\n'
                          '${climateText(t, c, year, locale)}',
                        ),
                      _climateSource(t, theme, places.first.$2),
                    ],
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

/// The forecast at each stage's highest point for its planned day, for the
/// stages planned within the forecast, and what is usual in its month for
/// those planned later. Nothing while loading or offline.
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
          for (final s in w?.stages ?? const <Never>[])
            if (s.day != null || s.climate != null) s,
        ];
        if (w == null || planned.isEmpty) return const SizedBox.shrink();
        final climate = planned.map((s) => s.climate).nonNulls.firstOrNull;
        return Column(
          key: const Key('weather'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text(t.weatherTitle, style: theme.textTheme.labelMedium),
            for (final s in planned)
              _line(
                theme,
                s.day == null ? null : WeatherIcon(s.day!.symbol),
                '${t.weatherStage(s.stage, forecastDate(s.day?.date ?? s.plannedDate!, locale))} · '
                '${s.point.name}, ${formatHeight(s.point.height)}\n'
                '${s.day != null ? forecastText(t, s.day!, locale) : climateText(t, s.climate!, int.parse(s.plannedDate!.substring(0, 4)), locale)}',
              ),
            _source(t, theme, w.run),
            if (climate != null) _climateSource(t, theme, climate),
          ],
        );
      },
    );
  }
}
