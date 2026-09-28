import 'api.dart';

/// Where public transport meets a journey or route: a stop ([at] its number)
/// or a point on the line ([at] lon,lat), on the stage's [day] if planned.
typedef TravelEnd = ({String at, String name, DateTime? day, List<List<double>> line});

String _coords(double lon, double lat) => '${lon.toStringAsFixed(5)},${lat.toStringAsFixed(5)}';

TravelEnd _end(Place? place, List<double> point, DateTime? day, List<List<double>> line, String unnamed) =>
    place != null && place.kind == 'pt_stop' && place.ref.isNotEmpty
    ? (at: place.ref, name: place.name, day: day, line: line)
    : (
        at: _coords(place?.lon ?? point[0], place?.lat ?? point[1]),
        name: place == null || place.name.isEmpty ? unnamed : place.name,
        day: day,
        line: line,
      );

/// The start of the first stage with a route and the end of the last, as on
/// the website (web/src/lib/travel/travel.ts). Points without a place get
/// the names given, for the walk to and from them.
({TravelEnd? start, TravelEnd? end}) journeyEnds(JourneyDetail j, {String start = '', String end = ''}) {
  final routed = [
    for (final s in j.stages)
      if (s.routeId != null && s.line.isNotEmpty) s,
  ];
  if (routed.isEmpty) return (start: null, end: null);
  final first = routed.first, last = routed.last;
  return (
    start: _end(first.start, first.line.first, first.plannedDate, first.line, start),
    end: _end(last.end, last.line.last, last.plannedDate, last.line, end),
  );
}

/// A route's start and end, named after its first and last point.
({TravelEnd? start, TravelEnd? end}) routeEnds(RouteDetail r, {String start = '', String end = ''}) {
  if (r.line.isEmpty) return (start: null, end: null);
  final anchors = r.json['anchors'] as List? ?? const [];
  String name(Object? a, String unnamed) => switch (a) {
    {'name': final String n} when n.isNotEmpty => n,
    _ => unnamed,
  };
  return (
    start: _end(null, r.line.first, null, r.line, name(anchors.firstOrNull, start)),
    end: _end(null, r.line.last, null, r.line, name(anchors.lastOrNull, end)),
  );
}

/// Where a way starts or ends away from the hike: a home or another place.
typedef Spot = ({String name, double lon, double lat});

/// The home or place of [way].
Spot? waySpot(TravelWay? way, Iterable<Home> homes) {
  if (way?.place case final p?) return p;
  final h = homes.where((h) => h.id == way?.homeId).firstOrNull;
  return h == null ? null : (name: h.name, lon: h.lon, lat: h.lat);
}

/// The connections from [home] (or another place) to the start ([to]) or
/// from the end home, with their ways; on [day] where the end has none.
Future<List<Trip>> travelTrips(Api api, Spot home, TravelEnd at, TravelWay way, {required bool to, DateTime? day}) {
  final here = _coords(home.lon, home.lat);
  // Names only for positions: stops have theirs.
  String? named(String place, String name) => place.contains(',') && name.isNotEmpty ? name : null;
  final (from, fromName, dest, destName) = to
      ? (here, home.name, at.at, named(at.at, at.name))
      : (at.at, named(at.at, at.name), here, home.name);
  return api.connections(
    from,
    dest,
    at.day ?? day ?? DateTime.now(),
    time: way.time,
    arrive: way.arrive,
    fromName: fromName,
    toName: destName,
    lines: true,
  );
}
