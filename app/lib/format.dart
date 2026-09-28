import 'package:intl/intl.dart';

/// Keeps a number and its unit on one line.
const _nbsp = '\u00a0';

/// Formats like the web app: hiking time rounded to 5 minutes.
String formatDuration(int seconds, [double pace = 1]) {
  final minutes = ((seconds * pace) / 60 / 5).round() * 5;
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m${_nbsp}min';
  return m == 0 ? '$h${_nbsp}h' : '$h${_nbsp}h $m${_nbsp}min';
}

/// «19.3 km» in German, «19,3 km» in French (the app's language, set in
/// main.dart); below a kilometre in metres.
String formatDistance(double metres, [String? language]) {
  if (metres < 1000) return formatHeight(metres);
  return '${NumberFormat('0.0', numberLocale(language)).format(metres / 1000)}${_nbsp}km';
}

/// The locale numbers are formatted in: the Swiss variants, as on the
/// website.
String numberLocale([String? language]) => switch (language ?? Intl.getCurrentLocale().split(RegExp('[_-]')).first) {
  'fr' => 'fr_CH',
  'it' => 'it_CH',
  'en' => 'en_GB',
  _ => 'de_CH',
};

/// Heights, ascents and short distances in whole metres: «1707 m».
String formatHeight(double metres) => '${metres.round()}${_nbsp}m';

String formatSac(int grade, int max) {
  if (grade == 0) return '–';
  return max > grade ? 'T$grade–T$max' : 'T$grade';
}

/// A date as in Switzerland: 23.09.2026.
String formatDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}.${l.month.toString().padLeft(2, '0')}.${l.year}';
}

/// A time of day, «16:05», in the phone's time zone.
String formatTime(DateTime t) {
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}
