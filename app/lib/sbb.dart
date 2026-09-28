/// Links into the SBB timetable, as on the website (web/src/lib/journeys/sbb.ts):
/// station names in von/nach, datum as dd.MM.yyyy.
const _base = {
  'de': 'https://www.sbb.ch/de/kaufen/pages/fahrplan/fahrplan.xhtml',
  'fr': 'https://www.sbb.ch/fr/acheter/pages/fahrplan/fahrplan.xhtml',
  'it': 'https://www.sbb.ch/it/acquistare/pages/fahrplan/fahrplan.xhtml',
  'en': 'https://www.sbb.ch/en/buying/pages/fahrplan/fahrplan.xhtml',
};

Uri sbbTimetable({String? from, String? to, DateTime? date, required String language}) {
  String two(int n) => n.toString().padLeft(2, '0');
  return Uri.parse(_base[language] ?? _base['de']!).replace(
    queryParameters: {
      'von': ?from,
      'nach': ?to,
      if (date != null) 'datum': '${two(date.day)}.${two(date.month)}.${date.year}',
      if (from != null && to != null) 'suche': 'true',
    },
  );
}
