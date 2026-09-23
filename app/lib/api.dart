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
  Me({required this.username, required this.displayName, required this.speedFactor});
  factory Me.fromJson(Map<String, dynamic> j) => Me(
    username: j['username'] as String,
    displayName: j['display_name'] as String,
    speedFactor: (j['speed_factor'] as num?)?.toDouble() ?? 1,
  );
  final String username;
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
      hikedAt = switch (j['hike']) {
        {'at': final String at} => DateTime.parse(at),
        _ => null,
      };
  final String id, title, owner;
  final Totals totals;

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
  Api(String server, {this.token, http.Client? client})
    : server = server.replaceAll(RegExp(r'/+$'), ''),
      _http = client ?? http.Client();

  final String server;
  String? token;
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
    return Me.fromJson(body['user'] as Map<String, dynamic>);
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

  Future<RouteDetail> route(String id) async => RouteDetail.fromJson(await _get('/routes/$id') as Map<String, dynamic>);

  /// The turns along a route, for spoken navigation; none where it does not
  /// follow the path network.
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
