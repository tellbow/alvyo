import 'dart:convert';

import 'package:http/http.dart' as http;

/// A failed API call with its HTTP status.
class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;

  @override
  String toString() => 'ApiException($status): $message';
}

/// The logged-in user.
class Me {
  Me({required this.id, required this.username, required this.displayName, required this.speedFactor});
  factory Me.fromJson(Map<String, dynamic> j) => Me(
    id: j['id'] as String,
    username: j['username'] as String,
    displayName: j['display_name'] as String,
    speedFactor: (j['speed_factor'] as num?)?.toDouble() ?? 1,
  );
  final String id, username;
  final String displayName;
  final double speedFactor;
}

/// The numbers of a route.
class Totals {
  Totals.fromJson(Map<String, dynamic> j)
    : distanceM = (j['distance_m'] as num).toDouble(),
      ascentM = (j['ascent_m'] as num).toDouble(),
      descentM = (j['descent_m'] as num).toDouble(),
      durationS = (j['duration_s'] as num).toInt(),
      sacGrade = (j['sac_grade'] as num).toInt(),
      sacMax = (j['sac_max'] as num).toInt();
  final double distanceM, ascentM, descentM;
  final int durationS, sacGrade, sacMax;
}

/// A route in lists.
class RouteSummary {
  RouteSummary.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      title = j['title'] as String,
      owner = j['owner_username'] as String,
      totals = Totals.fromJson(j['totals'] as Map<String, dynamic>),
      tags = _tags(j['tags']),
      hikedAt = switch (j['hike']) {
        {'at': final String at} => DateTime.parse(at),
        _ => null,
      };
  final String id, title, owner;
  final Totals totals;

  /// The owner's labels; a stage route has its journey's.
  final List<String> tags;

  /// When it was hiked, for hikes recorded with the app.
  final DateTime? hikedAt;
}

/// A route with its line (lon, lat, elevation per point).
class RouteDetail extends RouteSummary {
  RouteDetail.fromJson(super.j)
    : json = j,
      line = [
        for (final leg in j['legs'] as List)
          for (final c in (leg as Map<String, dynamic>)['coordinates'] as List)
            [for (final v in c as List) (v as num).toDouble()],
      ],
      super.fromJson();

  /// As the server sent it, to keep a copy offline.
  final Map<String, dynamic> json;
  final List<List<double>> line;

  /// The journey this route is a stage of, if it is one.
  String? get journeyId => json['journey_id'] as String?;
}

/// A junction where the route turns, [alongM] metres from its start; the
/// kind is left, sharp_right, keep_left, u_turn and so on.
class Turn {
  const Turn(this.alongM, this.kind);
  Turn.fromJson(Map<String, dynamic> j) : alongM = (j['along_m'] as num).toDouble(), kind = j['kind'] as String;
  final double alongM;
  final String kind;

  Map<String, dynamic> toJson() => {'along_m': alongM, 'kind': kind};
}

/// A journey in lists: a hike of several stages.
class JourneySummary {
  JourneySummary.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      title = j['title'] as String,
      stages = (j['stages'] as num).toInt(),
      stagesDone = (j['stages_done'] as num).toInt(),
      distanceM = (j['distance_m'] as num).toDouble(),
      ascentM = (j['ascent_m'] as num).toDouble(),
      durationS = (j['duration_s'] as num).toInt(),
      tags = _tags(j['tags']);

  /// The summary of a journey saved offline.
  JourneySummary.of(JourneyDetail j)
    : id = j.id,
      title = j.title,
      stages = j.stages.length,
      stagesDone = j.stagesDone,
      distanceM = j.totals.distanceM,
      ascentM = j.totals.ascentM,
      durationS = j.totals.durationS,
      tags = j.tags;
  final String id, title;
  final int stages, stagesDone, durationS;
  final double distanceM, ascentM;
  final List<String> tags;
}

/// Tags as the server sends them; none in copies saved before there were tags.
List<String> _tags(Object? v) => [for (final t in v as List? ?? const []) t as String];

/// A stage of a journey.
class Stage {
  Stage.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      version = (j['version'] as num?)?.toInt() ?? 1,
      title = j['title'] as String,
      plannedDate = switch (j['planned_date']) {
        final String d => DateTime.parse(d),
        _ => null,
      },
      status = j['status'] as String,
      transferBefore = j['transfer_before'] as String?,
      startPlace = (j['start_place'] as Map<String, dynamic>?)?['name'] as String?,
      endPlace = (j['end_place'] as Map<String, dynamic>?)?['name'] as String?,
      accommodation = j['accommodation'] as String? ?? '',
      booked = j['accommodation_booked'] as bool? ?? false,
      routeId = (j['route'] as Map<String, dynamic>?)?['id'] as String?,
      totals = switch (j['route']) {
        {'totals': final Map<String, dynamic> t} => Totals.fromJson(t),
        _ => null,
      },
      gapStatus = (j['gap'] as Map<String, dynamic>?)?['status'] as String?,
      gapM = ((j['gap'] as Map<String, dynamic>?)?['metres'] as num?)?.toDouble() ?? 0;
  final String id, title;

  /// Sent along when changing the stage, so as not to overwrite others.
  final int version;
  final DateTime? plannedDate;

  /// planned, done or skipped.
  final String status;

  /// How the gap to the previous stage is covered: pt, cablecar or other.
  final String? transferBefore;
  final String? startPlace, endPlace;
  final String accommodation;
  final bool booked;

  /// The stage's route, a route like the others; none planned yet if null.
  final String? routeId;
  final Totals? totals;

  /// To the end of the previous stage: ok, warning, gap or transfer.
  final String? gapStatus;
  final double gapM;
}

/// A journey with its stages.
class JourneyDetail {
  JourneyDetail.fromJson(this.json)
    : id = json['id'] as String,
      title = json['title'] as String,
      stages = [for (final s in json['stage_list'] as List) Stage.fromJson(s as Map<String, dynamic>)],
      totals = Totals.fromJson(json['totals'] as Map<String, dynamic>),
      stagesDone = ((json['progress'] as Map<String, dynamic>)['stages_done'] as num).toInt(),
      stagesTotal = ((json['progress'] as Map<String, dynamic>)['stages_total'] as num).toInt(),
      canEdit = json['can_edit'] as bool? ?? false,
      tags = _tags(json['tags']);

  /// As the server sent it, to keep a copy offline.
  final Map<String, dynamic> json;
  final String id, title;
  final List<String> tags;
  final List<Stage> stages;
  final Totals totals;

  /// Skipped stages do not count.
  final int stagesDone, stagesTotal;

  /// The combined profile of all stages: metres along (gaps between stages
  /// not counted), [lon, lat, elevation], and where each stage starts.
  ({List<double> distances, List<double> elevations, List<int> breaks}) get profile {
    final p = json['profile'] as Map<String, dynamic>? ?? const {};
    return (
      distances: [for (final d in p['distance'] as List? ?? const []) (d as num).toDouble()],
      elevations: [for (final pt in p['points'] as List? ?? const []) ((pt as List)[2] as num).toDouble()],
      breaks: [for (final b in p['breaks'] as List? ?? const []) (b as num).toInt()],
    );
  }

  /// The user may change it (owner or editor).
  final bool canEdit;
}

/// A protected area a route crosses: a wildlife rest area or a federal
/// hunting reserve.
class ProtectedArea {
  ProtectedArea.fromJson(Map<String, dynamic> j)
    : kind = j['kind'] as String,
      name = j['name'] as String,
      binding = j['binding'] as bool? ?? false,
      rule = {for (final e in (j['rule'] as Map<String, dynamic>).entries) e.key: e.value as String},
      period = switch (j['period']) {
        {'from': final String from, 'to': final String to} => (from: from, to: to),
        _ => null,
      },
      stages = [for (final s in j['stages'] as List? ?? const []) (s as num).toInt()];

  /// wildlife_rest or hunting_reserve.
  final String kind, name;
  final bool binding;

  /// The rule by language (de, fr, it, en).
  final Map<String, String> rule;

  /// When the rule applies, as MM-DD; null when always.
  final ({String from, String to})? period;

  /// The journey stages crossing it (from 1).
  final List<int> stages;

  /// The rule in [lang]; German where it has none.
  String ruleIn(String lang) => (rule[lang]?.isNotEmpty ?? false) ? rule[lang]! : rule['de'] ?? '';

  /// Whether [day] is in the period (always, without one).
  bool appliesOn(DateTime day) {
    final p = period;
    if (p == null) return true;
    final d = '${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return p.from.compareTo(p.to) <= 0
        ? d.compareTo(p.from) >= 0 && d.compareTo(p.to) <= 0
        : d.compareTo(p.from) >= 0 || d.compareTo(p.to) <= 0;
  }
}

/// Someone the hiker shares hikes with.
class Contact {
  Contact.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      email = j['email'] as String;
  final String id, name, email;
}

/// A hike shared with contacts.
class LiveShare {
  LiveShare.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      token = j['token'] as String? ?? '',
      expectedEnd = DateTime.parse(j['expected_end'] as String),
      recipients = [for (final r in j['recipients'] as List? ?? const []) r as String];

  /// The link is /live/{token}.
  final String id, token;
  final DateTime expectedEnd;
  final List<String> recipients;
}

/// One layer of an offline map on the server.
class PackFile {
  PackFile.fromJson(Map<String, dynamic> j)
    : layer = j['layer'] as String,
      name = j['name'] as String,
      bytes = (j['bytes'] as num).toInt();
  final String layer, name;
  final int bytes;
}

/// The offline map of a route on the server: missing, building, ready or
/// failed. The key changes when the route's line changes.
class PackStatus {
  PackStatus.fromJson(Map<String, dynamic> j)
    : state = j['state'] as String,
      key = j['key'] as String,
      done = (j['done'] as num).toInt(),
      total = (j['total'] as num).toInt(),
      files = [for (final f in j['files'] as List? ?? const []) PackFile.fromJson(f as Map<String, dynamic>)];
  final String state, key;
  final int done, total;
  final List<PackFile> files;
}

/// A point on the map.
typedef LonLat = ({double lon, double lat});

/// A map view: west, south, east, north.
typedef Bbox = ({double west, double south, double east, double north});

/// Lines as the server sends them: [lon, lat(, elevation)] per point.
List<List<double>> _line(Object? v) => [
  for (final c in v as List? ?? const []) [for (final x in c as List) (x as num).toDouble()],
];

/// A hut, hotel or campsite on the map (`GET /places/in-view`).
class Pin {
  Pin.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      kind = j['kind'] as String,
      name = j['name'] as String,
      detail = j['detail'] as String,
      lon = (j['lon'] as num).toDouble(),
      lat = (j['lat'] as num).toDouble(),
      website = j['website'] as String? ?? '';

  /// hut, hotel or campsite.
  final String id, kind, name;

  /// The OSM hut type, e.g. alpine_hut or wilderness_hut.
  final String detail;
  final double lon, lat;

  /// As OSM has it: free text, not always a link.
  final String website;
}

/// A search result (`GET /places/search`): a stop, hut, hotel, campsite, a
/// name from the national map or an address.
class FoundPlace {
  FoundPlace.fromJson(Map<String, dynamic> j)
    : name = j['name'] as String,
      kind = j['kind'] as String,
      detail = j['detail'] as String,
      lon = ((j['at'] as List)[0] as num).toDouble(),
      lat = ((j['at'] as List)[1] as num).toDouble();

  /// pt_stop, hut, hotel, campsite, name or address.
  final String name, kind;

  /// Stop modes, the OSM hut type, or the kind of name and its municipality.
  final String detail;
  final double lon, lat;
}

/// A place to start, end or spend the night at (`GET /places/nearby`, the
/// days of a planned journey).
class Place {
  Place.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      kind = j['kind'] as String,
      name = j['name'] as String,
      detail = j['detail'] as String? ?? '',
      lon = ((j['at'] as List)[0] as num).toDouble(),
      lat = ((j['at'] as List)[1] as num).toDouble(),
      distanceM = (j['distance_m'] as num?)?.toDouble() ?? 0,
      website = j['website'] as String? ?? '';

  /// pt_stop, hut, hotel or campsite.
  final String id, kind, name, detail;
  final double lon, lat, distanceM;
  final String website;
}

Place? _place(Object? v) => v is Map<String, dynamic> ? Place.fromJson(v) : null;

/// A point the planned route passes, as `POST /routes` takes it.
class Anchor {
  const Anchor(this.lon, this.lat, {this.name, this.straight = false, this.through});
  final double lon, lat;

  /// The place it was found as by search.
  final String? name;

  /// The leg arriving here is a straight line.
  final bool straight;

  /// The leg arriving here was dragged onto the path closest to this point.
  final LonLat? through;

  Map<String, dynamic> toJson() => {
    'lon': lon,
    'lat': lat,
    'name': ?name,
    if (straight) 'straight': true,
    if (through case final t?) 'through': {'lon': t.lon, 'lat': t.lat},
  };
}

/// The way between two points of a planned route (`POST /routing/leg`).
class Leg {
  Leg.fromJson(this.json)
    : line = _line(json['coordinates']),
      distanceM = (json['distance_m'] as num).toDouble(),
      ascentM = (json['ascent_m'] as num).toDouble(),
      descentM = (json['descent_m'] as num).toDouble(),
      durationS = (json['duration_s'] as num).toInt(),
      sacGrade = ((json['sac'] as Map<String, dynamic>)['grade'] as num).toInt(),
      sacMax = ((json['sac'] as Map<String, dynamic>)['max'] as num).toInt(),
      warnings = [for (final w in json['warnings'] as List? ?? const []) w as String];

  /// As the server sent it: goes back unchanged into `POST /routes`.
  final Map<String, dynamic> json;

  /// [lon, lat, elevation] per point.
  final List<List<double>> line;
  final double distanceM, ascentM, descentM;
  final int durationS, sacGrade, sacMax;

  /// e.g. snap_far_from, snap_far_to: a point is far from any path.
  final List<String> warnings;
}

/// A day of a planned journey (`POST /journeys/plan`).
class PlannedStage {
  PlannedStage.fromJson(this.json)
    : startPlace = _place(json['start_place']),
      endPlace = _place(json['end_place']),
      earlier = _place(json['earlier']),
      later = _place(json['later']),
      accommodation = json['accommodation'] as String? ?? '',
      totals = Totals.fromJson(json['totals'] as Map<String, dynamic>),
      overMax = json['over_max'] as bool? ?? false,
      underMin = json['under_min'] as bool? ?? false,
      line = [
        for (final leg in json['legs'] as List? ?? const []) ..._line((leg as Map<String, dynamic>)['coordinates']),
      ];

  /// As the server sent it; its anchors and legs go back into `POST /journeys`.
  final Map<String, dynamic> json;

  /// Where the previous day ended (none on the first) and where this one
  /// ends (none on the last).
  final Place? startPlace, endPlace;

  /// The nearest places before and after the end, to end the day there
  /// instead (see [Api.planJourney]'s ends).
  final Place? earlier, later;

  /// The hut, hotel or campsite; empty at a stop.
  final String accommodation;
  final Totals totals;

  /// Longer than the most per day (no place to end it earlier), or shorter
  /// than the least.
  final bool overMax, underMin;

  /// [lon, lat, elevation] per point, all legs joined.
  final List<List<double>> line;

  /// The stage as `POST /journeys` takes it.
  Map<String, dynamic> toInput({String? title}) => {
    'profile': json['profile'],
    'anchors': json['anchors'],
    'legs': json['legs'],
    'accommodation': accommodation,
    'title': ?title,
    'start_place_id': ?startPlace?.id,
    'end_place_id': ?endPlace?.id,
  };
}

/// A journey split into days; the target, least and most per day in
/// seconds of Swiss hiking time.
class Proposal {
  Proposal.fromJson(Map<String, dynamic> j)
    : stages = [for (final s in j['stages'] as List) PlannedStage.fromJson(s as Map<String, dynamic>)],
      targetS = (j['target_s'] as num).toInt(),
      minS = (j['min_s'] as num).toInt(),
      maxS = (j['max_s'] as num).toInt();
  final List<PlannedStage> stages;
  final int targetS, minS, maxS;
}

/// One of several ways (`POST /journeys/suggest`).
class Suggestion {
  Suggestion.fromJson(Map<String, dynamic> j)
    : points = [
        for (final p in j['points'] as List)
          (lon: ((p as Map<String, dynamic>)['lon'] as num).toDouble(), lat: (p['lat'] as num).toDouble()),
      ],
      via = j['via'] as String? ?? '',
      proposal = Proposal.fromJson(j['proposal'] as Map<String, dynamic>);

  /// The points asked for with the place passed: for [Api.planJourney] with
  /// ends, to move this way's nights.
  final List<LonLat> points;

  /// The village or hut the way passes; empty for the direct way.
  final String via;
  final Proposal proposal;
}

/// A public route or journey (`GET /discover`).
class DiscoverItem {
  DiscoverItem.fromJson(Map<String, dynamic> j)
    : kind = j['kind'] as String,
      id = j['id'] as String,
      title = j['title'] as String,
      owner = j['owner_username'] as String,
      distanceM = (j['distance_m'] as num).toDouble(),
      ascentM = (j['ascent_m'] as num).toDouble(),
      durationS = (j['duration_s'] as num).toInt(),
      longestS = (j['longest_s'] as num).toInt(),
      sacGrade = (j['sac_grade'] as num).toInt(),
      sacMax = (j['sac_max'] as num).toInt(),
      stages = (j['stages'] as num?)?.toInt() ?? 0,
      lines = [for (final l in j['lines'] as List? ?? const []) _line(l)];

  /// route or journey.
  final String kind, id, title, owner;
  final double distanceM, ascentM;

  /// Journeys: all stages together, and the longest stage; routes: both the
  /// route's.
  final int durationS, longestS;
  final int sacGrade, sacMax;

  /// Journeys only.
  final int stages;

  /// [lon, lat] per point; a journey has one line per stage.
  final List<List<List<double>>> lines;
}

/// Client of the Alvyo API. Logging in yields the session token, which
/// authenticates later calls as a Bearer token.
class Api {
  Api(String server, {this.token, this.userId, http.Client? client})
    : server = _normalized(server),
      _http = client ?? http.Client();

  /// Without trailing slashes, and https when typed without a scheme.
  static String _normalized(String server) {
    final s = server.trim().replaceAll(RegExp(r'/+$'), '');
    return s.contains('://') ? s : 'https://$s';
  }

  final String server;
  String? token;

  /// The logged-in account; recordings are kept for it (unknown until
  /// known once online, for sessions from before it was saved).
  String? userId;
  final http.Client _http;

  Uri _uri(String path) => Uri.parse('$server/api/v1$path');

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'User-Agent': 'alvyo-app',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  dynamic _decode(http.Response r) {
    if (r.statusCode >= 400) {
      var message = r.reasonPhrase ?? '';
      try {
        message = (jsonDecode(r.body) as Map<String, dynamic>)['detail'] as String? ?? message;
      } on FormatException {
        // not JSON
      }
      throw ApiException(r.statusCode, message);
    }
    return r.body.isEmpty ? null : jsonDecode(r.body);
  }

  Future<dynamic> _get(String path, [Map<String, Object>? query]) async => _decode(
    await _http.get(query == null ? _uri(path) : _uri(path).replace(queryParameters: query), headers: _headers),
  );

  /// Logs in with e-mail or username and password.
  Future<Me> login(String login, String password) async {
    final r = await _http.post(
      _uri('/auth/login'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'login': login, 'password': password}),
    );
    final body = _decode(r) as Map<String, dynamic>;
    final session = RegExp(r'alvyo_session=([^;,\s]+)').firstMatch(r.headers['set-cookie'] ?? '');
    if (session == null) throw ApiException(500, 'no session in the answer');
    token = session.group(1);
    final me = Me.fromJson(body['user'] as Map<String, dynamic>);
    userId = me.id;
    return me;
  }

  Future<void> logout() async {
    await _http.post(_uri('/auth/logout'), headers: _headers);
    token = null;
  }

  Future<Me> me() async => Me.fromJson(await _get('/me') as Map<String, dynamic>);

  /// The user's own routes, newest first.
  Future<List<RouteSummary>> routes() async {
    final j = await _get('/routes') as Map<String, dynamic>;
    return [for (final r in j['routes'] as List) RouteSummary.fromJson(r as Map<String, dynamic>)];
  }

  /// The user's own journeys.
  Future<List<JourneySummary>> journeys() async {
    final j = await _get('/journeys') as Map<String, dynamic>;
    return [for (final r in j['journeys'] as List) JourneySummary.fromJson(r as Map<String, dynamic>)];
  }

  Future<JourneyDetail> journey(String id) async =>
      JourneyDetail.fromJson(await _get('/journeys/$id') as Map<String, dynamic>);

  Future<RouteDetail> route(String id) async => RouteDetail.fromJson(await _get('/routes/$id') as Map<String, dynamic>);

  /// The turns along a route, for spoken navigation; none where it does not
  /// follow the path network.
  Future<List<Contact>> contacts() async {
    final j = await _get('/me/contacts') as Map<String, dynamic>;
    return [for (final c in j['contacts'] as List) Contact.fromJson(c as Map<String, dynamic>)];
  }

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final req = http.Request(method, _uri(path))..headers.addAll({..._headers, 'Content-Type': 'application/json'});
    if (body != null) req.body = jsonEncode(body);
    return _decode(await http.Response.fromStream(await _http.send(req)));
  }

  /// Shares a hike's position with [contactIds]; they get the link by e-mail.
  Future<LiveShare> startLive({
    String? routeId,
    required String title,
    required List<String> contactIds,
    required DateTime expectedEnd,
  }) async => LiveShare.fromJson(
    await _send('POST', '/live', {
          'route_id': ?routeId,
          'title': title,
          'contact_ids': contactIds,
          'expected_end': expectedEnd.toUtc().toIso8601String(),
        })
        as Map<String, dynamic>,
  );

  Future<void> livePositions(String id, List<({double lon, double lat, DateTime time})> points) =>
      _send('POST', '/live/$id/positions', {
        'points': [
          for (final p in points) {'lon': p.lon, 'lat': p.lat, 't': p.time.toUtc().toIso8601String()},
        ],
      });

  /// Moves the expected end («später»).
  Future<void> extendLive(String id, DateTime end) =>
      _send('PATCH', '/live/$id', {'expected_end': end.toUtc().toIso8601String()});

  Future<void> endLive(String id) => _send('POST', '/live/$id/end');

  /// The protected areas a route, or a journey's stages, cross.
  Future<List<ProtectedArea>> areas({String? routeId, String? journeyId}) async {
    final j =
        await _get(routeId != null ? '/routes/$routeId/areas' : '/journeys/$journeyId/areas') as Map<String, dynamic>;
    return [for (final a in j['areas'] as List) ProtectedArea.fromJson(a as Map<String, dynamic>)];
  }

  Future<List<Turn>> turns(String routeId) async {
    final j = await _get('/routes/$routeId/turns') as Map<String, dynamic>;
    return [for (final t in j['turns'] as List) Turn.fromJson(t as Map<String, dynamic>)];
  }

  /// Saves a recorded hike as a route; uploading the same [id] again is fine.
  /// Returns the route id.
  Future<String> uploadHike({
    required String id,
    String? routeId,
    required String title,
    required List<({double lon, double lat, DateTime time})> points,
  }) async {
    final r = await _http.post(
      _uri('/hikes'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'id': id,
        'route_id': ?routeId,
        'title': title,
        'points': [
          for (final p in points) {'lon': p.lon, 'lat': p.lat, 't': p.time.toUtc().toIso8601String()},
        ],
      }),
    );
    return (_decode(r) as Map<String, dynamic>)['id'] as String;
  }

  /// Marks a stage as hiked (on [day]) or as planned again. Fails with 412
  /// when someone changed the stage since it was loaded.
  Future<JourneyDetail> setStageDone(String journeyId, Stage stage, bool done, {DateTime? day}) async {
    final d = day ?? DateTime.now();
    final date =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final r = await _http.patch(
      _uri('/journeys/$journeyId/stages/${stage.id}'),
      headers: {..._headers, 'Content-Type': 'application/json', 'If-Match': '"${stage.version}"'},
      body: jsonEncode(done ? {'status': 'done', 'done_on': date} : {'status': 'planned', 'done_on': ''}),
    );
    return JourneyDetail.fromJson(_decode(r) as Map<String, dynamic>);
  }

  /// Huts, hotels and campsites in [view]; [kinds] of hut, hotel, campsite.
  Future<List<Pin>> placesInView(Bbox view, List<String> kinds) async {
    final j =
        await _get('/places/in-view', {
              'bbox': [view.west, view.south, view.east, view.north].map((v) => v.toStringAsFixed(5)).join(','),
              'kind': kinds,
            })
            as Map<String, dynamic>;
    return [for (final p in j['places'] as List) Pin.fromJson(p as Map<String, dynamic>)];
  }

  /// Places, names and addresses matching [q] (2 characters at least);
  /// among equally good ones the nearest to [near] first. Needs a login.
  Future<List<FoundPlace>> searchPlaces(String q, {LonLat? near}) async {
    // The server takes a centre in Switzerland only.
    final inCh = near != null && near.lon >= 5.9 && near.lon <= 10.6 && near.lat >= 45.8 && near.lat <= 47.9;
    final j =
        await _get('/places/search', {'q': q, if (inCh) 'lon': '${near.lon}', if (inCh) 'lat': '${near.lat}'})
            as Map<String, dynamic>;
    return [for (final p in j['places'] as List) FoundPlace.fromJson(p as Map<String, dynamic>)];
  }

  /// Stops, huts, hotels and campsites near [at], nearest first; [q] widens
  /// the search to 30 km. [kinds] of pt_stop, hut, hotel, campsite; all if none.
  Future<List<Place>> placesNearby(LonLat at, {String? q, List<String> kinds = const [], int? limit}) async {
    final j =
        await _get('/places/nearby', {
              'lon': '${at.lon}',
              'lat': '${at.lat}',
              if (q != null && q.isNotEmpty) 'q': q,
              if (kinds.isNotEmpty) 'kind': kinds.join(','),
              if (limit != null) 'limit': '$limit',
            })
            as Map<String, dynamic>;
    return [for (final p in j['places'] as List) Place.fromJson(p as Map<String, dynamic>)];
  }

  /// The way from [from] to [to] on paths ([profile] hike: up to T3, alpine:
  /// up to T6), or a [straight] line; [through] a point the way passes
  /// closest to. Fails with 422 when there is no way.
  Future<Leg> leg(LonLat from, LonLat to, {String profile = 'hike', bool straight = false, LonLat? through}) async =>
      Leg.fromJson(
        await _send('POST', '/routing/leg', {
              'from': {'lon': from.lon, 'lat': from.lat},
              'to': {'lon': to.lon, 'lat': to.lat},
              'profile': profile,
              'straight': straight,
              if (through != null) 'through': {'lon': through.lon, 'lat': through.lat},
            })
            as Map<String, dynamic>,
      );

  /// Saves a planned route: its [anchors] and the [legs] between them.
  Future<RouteDetail> createRoute({
    required String title,
    required String profile,
    required List<Anchor> anchors,
    required List<Leg> legs,
    String visibility = 'private',
    List<String> tags = const [],
  }) async => RouteDetail.fromJson(
    await _send('POST', '/routes', {
          'title': title,
          'profile': profile,
          'visibility': visibility,
          'tags': tags,
          'anchors': [for (final a in anchors) a.toJson()],
          'legs': [for (final l in legs) l.json],
        })
        as Map<String, dynamic>,
  );

  /// The protected areas a line ([lon, lat] points) crosses, before it is saved.
  Future<List<ProtectedArea>> lineAreas(List<List<double>> line) async {
    final j =
        await _send('POST', '/routing/areas', {
              'line': [
                for (final c in line) [c[0], c[1]],
              ],
            })
            as Map<String, dynamic>;
    return [for (final a in j['areas'] as List) ProtectedArea.fromJson(a as Map<String, dynamic>)];
  }

  /// What `POST /journeys/plan` and `/journeys/suggest` take. Hours are Swiss
  /// hiking time (divide the hiker's hours by [Me.speedFactor]).
  static Map<String, dynamic> _journeyRequest(
    List<LonLat> points,
    String profile,
    int? days,
    double? hoursPerDay,
    double? minHours,
    double? maxHours,
    List<String> kinds,
  ) => {
    'points': [
      for (final p in points) {'lon': p.lon, 'lat': p.lat},
    ],
    'profile': profile,
    'days': ?days,
    'hours_per_day': ?hoursPerDay,
    'min_hours': ?minHours,
    'max_hours': ?maxHours,
    'kinds': kinds,
  };

  /// Splits the way through [points] into days: [days], or [hoursPerDay], or
  /// as few days as fit between [minHours] and [maxHours] ([maxHours] alone
  /// with the others: the most per day). The nights at [kinds] (hut, hotel,
  /// campsite, pt_stop; all if none); [ends] are place ids to end the days
  /// at instead (a stage's earlier or later). Fails with 422 when there is
  /// no way.
  Future<Proposal> planJourney({
    required List<LonLat> points,
    String profile = 'hike',
    int? days,
    double? hoursPerDay,
    double? minHours,
    double? maxHours,
    List<String> kinds = const [],
    List<String>? ends,
  }) async => Proposal.fromJson(
    await _send('POST', '/journeys/plan', {
          ..._journeyRequest(points, profile, days, hoursPerDay, minHours, maxHours, kinds),
          'ends': ?ends,
        })
        as Map<String, dynamic>,
  );

  /// Up to four ways through [points], each split into days as by
  /// [planJourney], shortest first. Nothing is saved.
  Future<List<Suggestion>> suggestJourneys({
    required List<LonLat> points,
    String profile = 'hike',
    int? days,
    double? hoursPerDay,
    double? minHours,
    double? maxHours,
    List<String> kinds = const [],
  }) async {
    final j =
        await _send(
              'POST',
              '/journeys/suggest',
              _journeyRequest(points, profile, days, hoursPerDay, minHours, maxHours, kinds),
            )
            as Map<String, dynamic>;
    return [for (final s in j['suggestions'] as List) Suggestion.fromJson(s as Map<String, dynamic>)];
  }

  /// Creates a journey with a route per planned stage.
  Future<JourneyDetail> createJourney({
    required String title,
    required List<PlannedStage> stages,
    String visibility = 'private',
  }) async => JourneyDetail.fromJson(
    await _send('POST', '/journeys', {
          'title': title,
          'visibility': visibility,
          'stages': [for (final s in stages) s.toInput()],
        })
        as Map<String, dynamic>,
  );

  /// Public routes and journeys in [view]: [kind] route or journey (both if
  /// null), at most [sacMax] (any if 0), hiking time in seconds (Swiss; for
  /// journeys of the longest stage). [more]: zoom in or narrow the filters.
  Future<({List<DiscoverItem> items, bool more})> discover(
    Bbox view, {
    String? kind,
    int sacMax = 0,
    int? durationMin,
    int? durationMax,
  }) async {
    final j =
        await _get('/discover', {
              'bbox': [view.west, view.south, view.east, view.north].map((v) => v.toStringAsFixed(4)).join(','),
              'kind': ?kind,
              if (sacMax > 0) 'sac_max': '$sacMax',
              if (durationMin != null) 'duration_min': '$durationMin',
              if (durationMax != null) 'duration_max': '$durationMax',
            })
            as Map<String, dynamic>;
    return (
      items: [for (final i in j['items'] as List) DiscoverItem.fromJson(i as Map<String, dynamic>)],
      more: j['more'] as bool? ?? false,
    );
  }

  /// Has the server build the offline map of a route, unless it is built.
  Future<PackStatus> buildPack(String routeId) async => PackStatus.fromJson(
    _decode(await _http.post(_uri('/routes/$routeId/pack'), headers: _headers)) as Map<String, dynamic>,
  );

  Future<PackStatus> packStatus(String routeId) async =>
      PackStatus.fromJson(await _get('/routes/$routeId/pack') as Map<String, dynamic>);

  /// Starts the download of one layer of a route's offline map (PMTiles),
  /// [from] a byte offset to continue a broken off download (206 then).
  Future<http.StreamedResponse> packFile(String routeId, String layer, {int from = 0}) async {
    final req = http.Request('GET', _uri('/routes/$routeId/pack/$layer'))..headers.addAll(_headers);
    if (from > 0) req.headers['Range'] = 'bytes=$from-';
    final r = await _http.send(req);
    if (r.statusCode >= 400) _decode(await http.Response.fromStream(r));
    return r;
  }
}
