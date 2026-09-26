/// Putting a journey together from suggested ways, as the website does
/// (web/src/lib/journeys/suggestions.ts). A way is given by the place id
/// each of its days ends at (null: the destination).
library;

/// A day of the journey being put together: the way and its day.
typedef Picked = ({int way, int stage});

/// All days of one way.
List<Picked> whole(List<List<String?>> ways, int way) => [
  for (var stage = 0; stage < ways[way].length; stage++) (way: way, stage: stage),
];

/// The days' stages, from [stages] per way.
List<T> stagesOf<T>(List<List<T>> stages, List<Picked> picked) => [for (final p in picked) stages[p.way][p.stage]];

/// The one way all days come from; null when put together.
int? single(List<List<String?>> ways, List<Picked> picked) {
  if (picked.isEmpty) return null;
  final w = picked.first.way;
  return picked.length == ways[w].length && picked.every((p) => p.way == w) ? w : null;
}

/// The other ways that sleep where day [i] ends, each with its day ending
/// there: the journey can go on along them.
List<Picked> switches(List<List<String?>> ways, List<Picked> picked, int i) {
  final p = picked[i];
  final end = ways[p.way][p.stage];
  if (end == null) return const [];
  return [
    for (var way = 0; way < ways.length; way++)
      if (way != p.way)
        if (ways[way].indexOf(end) case final stage when stage >= 0) (way: way, stage: stage),
  ];
}

/// The days up to day [i], then along the way of [to] after its day.
List<Picked> switchTo(List<List<String?>> ways, List<Picked> picked, int i, Picked to) => [
  ...picked.take(i + 1),
  ...whole(ways, to.way).skip(to.stage + 1),
];
