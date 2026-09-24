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

/// Client of the odysgeh API. Logging in yields the session token, which
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
    'User-Agent': 'odysgeh-app',
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

  Future<dynamic> _get(String path) async => _decode(await _http.get(_uri(path), headers: _headers));

  /// Logs in with e-mail or username and password.
  Future<Me> login(String login, String password) async {
    final r = await _http.post(
      _uri('/auth/login'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'login': login, 'password': password}),
    );
    final body = _decode(r) as Map<String, dynamic>;
    final session = RegExp(r'odysgeh_session=([^;,\s]+)').firstMatch(r.headers['set-cookie'] ?? '');
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
