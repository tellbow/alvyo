/// Formats like the web app: hiking time rounded to 5 minutes.
String formatDuration(int seconds, [double pace = 1]) {
  final minutes = ((seconds * pace) / 60 / 5).round() * 5;
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

String formatDistance(double metres) =>
    metres < 1000 ? '${metres.round()} m' : '${(metres / 1000).toStringAsFixed(1)} km';

String formatSac(int grade, int max) {
  if (grade == 0) return '–';
  return max > grade ? 'T$grade–T$max' : 'T$grade';
}
