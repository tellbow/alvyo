import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'format.dart';
import 'precip.dart';
import 'snow.dart';

/// A failed API call with its HTTP status.
class ApiException implements Exception {
  ApiException(this.status, this.message, [this.errors = const []]);
  final int status;
  final String message;

  /// The details the server gave, e.g. which field is wrong.
  final List<Map<String, dynamic>> errors;

  /// From a multi-day plan refused for a day over the most per day: the
  /// fewest days that fit (0: none do, too few places to sleep); null when
  /// refused for another reason.
  int? get fewestDays {
    for (final e in errors) {
      if (e['message'] == 'fewest days that fit') return (e['value'] as num?)?.toInt() ?? 0;
    }
    return null;
  }

  @override
  String toString() => 'ApiException($status): $message';
}

/// The logged-in user.
class Me {
  Me({
    required this.id,
    required this.username,
    required this.displayName,
    required this.speedFactor,
    this.email = '',
    this.locale = 'de',
    this.hasPassword = true,
    this.notifyComments = false,
    this.notifyFollows = false,
    this.emailVerified = true,
    this.profilePublic = true,
    this.friendRequests = 0,
  });
  factory Me.fromJson(Map<String, dynamic> j) => Me(
    id: j['id'] as String,
    username: j['username'] as String,
    displayName: j['display_name'] as String,
    speedFactor: (j['speed_factor'] as num?)?.toDouble() ?? 1,
    email: j['email'] as String? ?? '',
    locale: j['locale'] as String? ?? 'de',
    hasPassword: j['has_password'] as bool? ?? true,
    notifyComments: j['notify_comments'] as bool? ?? false,
    notifyFollows: j['notify_follows'] as bool? ?? false,
    emailVerified: j['email_verified'] as bool? ?? true,
    profilePublic: j['profile_public'] as bool? ?? true,
    friendRequests: (j['friend_requests'] as num?)?.toInt() ?? 0,
  );
  final String id, username;
  final String displayName;
  final double speedFactor;
  final String email;

  /// The language of e-mails.
  final String locale;

  /// False for accounts made through a sign-in provider: deleting the
  /// account then needs a recent login instead of the password.
  final bool hasPassword;

  /// E-mails on comments on one's routes and journeys, and on new followers.
  final bool notifyComments, notifyFollows;

  /// Only verified accounts publish, share and comment.
  final bool emailVerified;

  /// Found by the user search; a private profile is seen by friends only.
  final bool profilePublic;

  /// Friend requests waiting for an answer.
  final int friendRequests;
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
      },
      doneOn = j['done_on'] as String?;
  final String id, title, owner;
  final Totals totals;

  /// When the user hiked it (YYYY-MM-DD): marked, or recorded with the app.
  final String? doneOn;

  /// The owner's labels; a stage route has its journey's.
  final List<String> tags;

  /// When it was hiked, for hikes recorded with the app.
  final DateTime? hikedAt;
}

/// Someone who comes along on a journey, and the ids of their stages.
class Person {
  Person.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      username = j['username'] as String? ?? '',
      displayName = j['display_name'] as String? ?? '',
      email = j['email'] as String? ?? '',
      stages = [for (final s in j['stages'] as List) s as String];
  final String id, username, displayName;

  /// For the owner, for invitations by address.
  final String email;
  final List<String> stages;

  /// The account's name, else the address invited (owner), else empty.
  String get name => displayName.isNotEmpty
      ? displayName
      : username.isNotEmpty
      ? username
      : email;
}

/// A route with its line (lon, lat, elevation per point).
/// An official Wanderland route (ASTRA / SchweizMobil): its number at
/// SchweizMobil and its kind (national, regional, local, handicap).
class Official {
  const Official(this.number, this.kind);

  /// Null unless [j] is one.
  static Official? of(Object? j) => switch (j) {
    {'number': final String number, 'kind': final String kind} => Official(number, kind),
    _ => null,
  };

  final String number, kind;
}

class RouteDetail extends RouteSummary {
  RouteDetail.fromJson(super.j)
    : json = j,
      doneMarked = j['done_marked'] as bool? ?? false,
      line = [
        for (final leg in j['legs'] as List)
          for (final c in (leg as Map<String, dynamic>)['coordinates'] as List)
            [for (final v in c as List) (v as num).toDouble()],
      ],
      super.fromJson();

  /// As the server sent it, to keep a copy offline.
  final Map<String, dynamic> json;
  final List<List<double>> line;

  /// doneOn is the user's own mark, which they can take back.
  final bool doneMarked;

  /// The journey this route is a stage of, if it is one.
  String? get journeyId => json['journey_id'] as String?;

  /// Set for the official Wanderland routes and their stages.
  Official? get official => Official.of(json['official']);

  /// The user may change it: not so for others' public routes (e.g. from
  /// discovering). Copies saved before the server sent it are the user's.
  bool get canEdit => json['can_edit'] as bool? ?? true;

  /// The user owns it and may delete it.
  bool get isOwner => json['role'] == 'owner';

  String get description => json['description'] as String? ?? '';

  /// private, unlisted or public.
  String get visibility => json['visibility'] as String? ?? 'private';

  /// Sent along when changing the route, so as not to overwrite others.
  int get version => (json['version'] as num?)?.toInt() ?? 1;

  /// For the owner: the link of an unlisted route is /routes/{id}?t=token.
  String? get shareToken => json['share_token'] as String?;

  /// hike or alpine.
  String get profile => json['profile'] as String? ?? 'hike';

  /// The points it was planned through.
  List<Anchor> get anchors => [
    for (final a in json['anchors'] as List? ?? const [])
      if (a case final Map<String, dynamic> m)
        Anchor(
          (m['lon'] as num).toDouble(),
          (m['lat'] as num).toDouble(),
          name: m['name'] as String?,
          straight: m['straight'] as bool? ?? false,
          alpine: m['alpine'] as bool? ?? false,
          through: switch (m['through']) {
            {'lon': final num lon, 'lat': final num lat} => (lon: lon.toDouble(), lat: lat.toDouble()),
            _ => null,
          },
        ),
  ];

  /// The legs between the anchors, as the server keeps them.
  List<Leg> get legs => [for (final l in json['legs'] as List? ?? const []) Leg.fromJson(l as Map<String, dynamic>)];
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
      tags = _tags(j['tags']),
      owner = j['owner_username'] as String? ?? '',
      doneOn = j['done_on'] as String?;

  /// The summary of a journey saved offline.
  JourneySummary.of(JourneyDetail j)
    : id = j.id,
      title = j.title,
      owner = j.owner,
      stages = j.stages.length,
      stagesDone = j.stagesDone,
      distanceM = j.totals.distanceM,
      ascentM = j.totals.ascentM,
      durationS = j.totals.durationS,
      tags = j.tags,
      doneOn = j.doneOn;
  final String id, title, owner;
  final int stages, stagesDone, durationS;

  /// When the user finished it (YYYY-MM-DD): marked, or all stages ticked off.
  final String? doneOn;
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
      start = _stagePlace(j['start_place']),
      end = _stagePlace(j['end_place']),
      notes = j['notes'] as String? ?? '',
      accommodation = j['accommodation'] as String? ?? '',
      booked = j['accommodation_booked'] as bool? ?? false,
      routeId = (j['route'] as Map<String, dynamic>?)?['id'] as String?,
      line = _line((j['route'] as Map<String, dynamic>?)?['line']),
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

  /// The places as the server sent them: stops have a timetable [Place.ref].
  final Place? start, end;
  final String notes;
  final String accommodation;
  final bool booked;

  /// The stage's route, a route like the others; none planned yet if null.
  final String? routeId;

  /// The route's line, [lon, lat(, elevation)] per point; empty without one
  /// (and in copies saved before it was kept).
  final List<List<double>> line;
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
      tags = _tags(json['tags']),
      doneOn = json['done_on'] as String?,
      doneMarked = json['done_marked'] as bool? ?? false;

  /// As the server sent it, to keep a copy offline.
  final Map<String, dynamic> json;
  final String id, title;
  final List<String> tags;
  final List<Stage> stages;
  final Totals totals;

  /// Skipped stages do not count.
  final int stagesDone, stagesTotal;

  /// When the user finished it (YYYY-MM-DD), and whether by their own mark.
  final String? doneOn;
  final bool doneMarked;

  /// The combined profile of all stages: metres along (gaps between stages
  /// not counted), [lon, lat, elevation], and where each stage starts.
  /// Each routed stage's line (lon, lat, elevation), from the profile's
  /// samples: the stage's index (from 0) and its points.
  List<(int, List<List<double>>)> get stageLines {
    final p = json['profile'] as Map<String, dynamic>? ?? const {};
    final points = [
      for (final pt in p['points'] as List? ?? const []) [for (final v in pt as List) (v as num).toDouble()],
    ];
    final breaks = [for (final b in p['breaks'] as List? ?? const []) (b as num).toInt()];
    final routed = [
      for (final (i, s) in stages.indexed)
        if (s.routeId != null) i,
    ];
    return [
      for (final (k, start) in breaks.indexed)
        if (k < routed.length)
          (
            routed[k],
            points.sublist(
              start.clamp(0, points.length),
              (k + 1 < breaks.length ? breaks[k + 1] : points.length).clamp(0, points.length),
            ),
          ),
    ];
  }

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

  /// The user owns it and may delete it.
  bool get isOwner => json['role'] == 'owner';

  String get owner => json['owner_username'] as String? ?? '';
  String get description => json['description'] as String? ?? '';

  /// Set for the official Wanderland routes.
  Official? get official => Official.of(json['official']);

  /// private, unlisted or public.
  String get visibility => json['visibility'] as String? ?? 'private';

  /// Sent along when changing the journey, so as not to overwrite others.
  int get version => (json['version'] as num?)?.toInt() ?? 1;

  /// For the owner: the link of an unlisted journey is /journeys/{id}?t=token.
  String? get shareToken => json['share_token'] as String?;
}

/// A summit, viewpoint, waterfall, drinking water or shelter along a route.
class Poi {
  Poi.fromJson(Map<String, dynamic> j)
    : kind = j['kind'] as String,
      name = j['name'] as String? ?? '',
      ele = (j['ele'] as num?)?.toInt(),
      lon = ((j['at'] as List?)?[0] as num?)?.toDouble() ?? 0,
      lat = ((j['at'] as List?)?[1] as num?)?.toDouble() ?? 0,
      alongM = (j['along_m'] as num).toDouble();

  /// peak, viewpoint, waterfall, water, shelter, firepit, picnic,
  /// restaurant, toilets or cablecar.
  final String kind;

  /// Empty for many drinking water points, shelters, fire places and toilets.
  final String name;

  /// Summits: height in metres.
  final int? ele;
  final double lon, lat, alongM;

  /// As a place on the map, to show when tapped.
  Pin toPin(int i) => Pin.fromJson({
    'id': 'along-$i',
    'kind': kind,
    'name': name,
    'detail': ele?.toString() ?? '',
    'lon': lon,
    'lat': lat,
  });
}

/// MeteoSwiss's forecast of one day at a point.
class ForecastDay {
  ForecastDay.fromJson(Map<String, dynamic> j)
    : date = j['date'] as String,
      minC = (j['min_c'] as num).toDouble(),
      maxC = (j['max_c'] as num).toDouble(),
      rainMm = (j['rain_mm'] as num).toDouble(),
      rainLoMm = (j['rain_lo_mm'] as num).toDouble(),
      rainHiMm = (j['rain_hi_mm'] as num).toDouble(),
      symbol = (j['symbol'] as num?)?.toInt();

  /// YYYY-MM-DD.
  final String date;
  final double minC, maxC;

  /// Precipitation, and the range it likely stays in.
  final double rainMm, rainLoMm, rainHiMm;

  /// MeteoSwiss's pictogram number (weather_symbols.dart).
  final int? symbol;
}

/// What is usual at a place in a month (MeteoSwiss's climate normals
/// 1991–2020), for a day beyond the forecast.
class Climate {
  Climate.fromJson(Map<String, dynamic> j)
    : month = (j['month'] as num).toInt(),
      station = j['station'] as String,
      rainStation = j['rain_station'] as String,
      minC = (j['min_c'] as num).toDouble(),
      maxC = (j['max_c'] as num).toDouble(),
      rainMm = (j['rain_mm'] as num).toDouble(),
      rainDays = (j['rain_days'] as num).toDouble();

  final int month;

  /// Where the temperatures (carried to the place's height) and the
  /// precipitation were measured.
  final String station, rainStation;
  final double minC, maxC, rainMm, rainDays;
}

Climate? _climate(Object? j) => j == null ? null : Climate.fromJson(j as Map<String, dynamic>);

/// A place MeteoSwiss forecasts for.
typedef ForecastPoint = ({String name, double height});

ForecastPoint _forecastPoint(Map<String, dynamic> j) =>
    (name: j['name'] as String, height: (j['height'] as num).toDouble());

/// The forecast at a route's start, highest point and end (one place may be
/// several of them), from today on.
class RouteWeather {
  RouteWeather.fromJson(Map<String, dynamic> j)
    : run = DateTime.parse(j['run'] as String),
      places = [
        for (final p in j['places'] as List)
          (
            roles: [for (final r in (p as Map<String, dynamic>)['roles'] as List) r as String],
            point: _forecastPoint(p['point'] as Map<String, dynamic>),
            days: [for (final d in p['days'] as List) ForecastDay.fromJson(d as Map<String, dynamic>)],
            climate: _climate(p['climate']),
          ),
      ];

  final DateTime run;

  /// roles: start, top, end; climate for a date asked for beyond the
  /// forecast.
  final List<({List<String> roles, ForecastPoint point, List<ForecastDay> days, Climate? climate})> places;
}

/// The forecast at each stage's highest point; [day] for a planned day
/// within the forecast.
class JourneyWeather {
  JourneyWeather.fromJson(Map<String, dynamic> j)
    : run = DateTime.parse(j['run'] as String),
      stages = [
        for (final s in j['stages'] as List)
          (
            stage: ((s as Map<String, dynamic>)['stage'] as num).toInt(),
            point: _forecastPoint(s['point'] as Map<String, dynamic>),
            day: s['day'] == null ? null : ForecastDay.fromJson(s['day'] as Map<String, dynamic>),
            climate: _climate(s['climate']),
            plannedDate: s['planned_date'] as String?,
          ),
      ];

  final DateTime run;

  /// [climate] for a planned day beyond the forecast.
  final List<({int stage, ForecastPoint point, ForecastDay? day, Climate? climate, String? plannedDate})> stages;
}

/// What lies along a route: protected areas, closures and shooting.
typedef Along = ({List<ProtectedArea> areas, List<Notice> notices});

/// Lines of [lon, lat]: where a route crosses something, for the map.
List<List<List<double>>> _parts(Object? v) => [
  for (final part in v as List? ?? const [])
    [
      for (final c in part as List) [for (final x in c as List) (x as num).toDouble()],
    ],
];

/// The snow along a route or a journey's stages, from the newest day of the
/// snow cover (satellite, 60 m).
class SnowAlong {
  SnowAlong.fromJson(Map<String, dynamic> j)
    : date = j['date'] as String?,
      snowM = (j['snow_m'] as num? ?? 0).toDouble(),
      steepM = (j['steep_m'] as num? ?? 0).toDouble(),
      patchesM = (j['patches_m'] as num? ?? 0).toDouble(),
      slopes = j['slopes'] as bool? ?? false,
      stretches = [
        for (final s in j['stretches'] as List? ?? const [])
          (
            fromM: ((s as Map<String, dynamic>)['from_m'] as num).toDouble(),
            toM: (s['to_m'] as num).toDouble(),
            steepM: (s['steep_m'] as num? ?? 0).toDouble(),
            line: _parts([s['line']]).first,
            stage: (s['stage'] as num?)?.toInt(),
          ),
      ],
      attribution = j['attribution'] as String? ?? '';

  /// The day of the snow cover (YYYY-MM-DD); null while there is none.
  final String? date;

  /// In snow (from 50 %), of that on terrain steeper than 30°, and patches
  /// elsewhere; each 0 below 100 m.
  final double snowM, steepM, patchesM;

  /// Whether the terrain's slope is known (Switzerland).
  final bool slopes;

  /// The stretches in snow, measured from the start (of the stage).
  final List<({double fromM, double toM, double steepM, List<List<double>> line, int? stage})> stretches;

  /// The credit the data policy asks for.
  final String attribution;
}

/// A closed trail or army shooting on the way.
class Notice {
  Notice.fromJson(Map<String, dynamic> j)
    : kind = j['kind'] as String,
      title = _texts(j['title']),
      reason = _texts(j['reason']),
      from = j['from'] as String?,
      to = j['to'] as String?,
      days = [
        for (final d in j['days'] as List? ?? const [])
          (
            date: (d as Map<String, dynamic>)['date'] as String,
            from: d['from'] as String? ?? '',
            to: d['to'] as String? ?? '',
          ),
      ],
      phone = j['phone'] as String? ?? '',
      stages = [for (final s in j['stages'] as List? ?? const []) (s as num).toInt()],
      where = _parts(j['where']);

  static Map<String, String> _texts(Object? m) => {
    for (final e in (m as Map<String, dynamic>? ?? const {}).entries)
      if (e.value case final String v when v.isNotEmpty) e.key: v,
  };

  /// closure or shooting.
  final String kind;

  /// By language (de, fr, it, en); German where one is missing.
  final Map<String, String> title, reason;

  /// Closures: closed from … to (YYYY-MM-DD).
  final String? from, to;

  /// Shooting: the days (YYYY-MM-DD), the hours as «0800», empty for all day.
  final List<({String date, String from, String to})> days;
  final String phone;
  final List<int> stages;

  /// The parts of the line concerned, for the map.
  final List<List<List<double>>> where;

  String titleIn(String lang) => title[lang] ?? title['de'] ?? '';
  String reasonIn(String lang) => reason[lang] ?? reason['de'] ?? '';

  /// Whether it concerns [day].
  bool on(DateTime day) {
    final d = day.toIso8601String().substring(0, 10);
    if (kind == 'shooting') return days.any((x) => x.date == d);
    return (from == null || d.compareTo(from!) >= 0) && (to == null || d.compareTo(to!) <= 0);
  }
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
      stages = [for (final s in j['stages'] as List? ?? const []) (s as num).toInt()],
      where = _parts(j['where']);

  /// wildlife_rest or hunting_reserve.
  final String kind, name;
  final bool binding;

  /// The rule by language (de, fr, it, en).
  final Map<String, String> rule;

  /// When the rule applies, as MM-DD; null when always.
  final ({String from, String to})? period;

  /// The journey stages crossing it (from 1).
  final List<int> stages;

  /// The parts of the line in it, for the map.
  final List<List<List<double>>> where;

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

/// What one reaches within [hours]: an outline, the outer ring first,
/// [lon, lat] per point.
class ReachArea {
  ReachArea.fromJson(Map<String, dynamic> j)
    : hours = (j['hours'] as num).toInt(),
      outline = [
        for (final ring in j['outline'] as List)
          [
            for (final p in ring as List) [((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()],
          ],
      ];
  final int hours;
  final List<List<List<double>>> outline;
}

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
      website = j['website'] as String? ?? '',
      ref = j['ref'] as String? ?? '';

  /// pt_stop, hut, hotel or campsite.
  final String id, kind, name, detail;
  final double lon, lat, distanceM;
  final String website;

  /// A stop's number for timetable queries ([Api.connections]).
  final String ref;
}

Place? _place(Object? v) => v is Map<String, dynamic> ? Place.fromJson(v) : null;

/// A stage's place; none where only its name is known.
Place? _stagePlace(Object? v) =>
    v is Map<String, dynamic> && v['id'] is String && v['at'] is List ? Place.fromJson(v) : null;

/// A point the planned route passes, as `POST /routes` takes it.
class Anchor {
  const Anchor(this.lon, this.lat, {this.name, this.straight = false, this.alpine = false, this.through});
  final double lon, lat;

  /// The place it was found as by search.
  final String? name;

  /// The leg arriving here is a straight line.
  final bool straight;

  /// The leg arriving here uses the alpine profile on a hike route.
  final bool alpine;

  /// The leg arriving here was dragged onto the path closest to this point.
  final LonLat? through;

  Map<String, dynamic> toJson() => {
    'lon': lon,
    'lat': lat,
    'name': ?name,
    if (straight) 'straight': true,
    if (alpine) 'alpine': true,
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
      warnings = [for (final w in json['warnings'] as List? ?? const []) w as String],
      alpine = switch (json['alpine']) {
        {'distance_m': final num m, 'sac_grade': final num g} => (distanceM: m.toDouble(), sacGrade: g.toInt()),
        _ => null,
      };

  /// As the server sent it: goes back unchanged into `POST /routes`.
  final Map<String, dynamic> json;

  /// [lon, lat, elevation] per point.
  final List<List<double>> line;
  final double distanceM, ascentM, descentM;
  final int durationS, sacGrade, sacMax;

  /// e.g. snap_far_from, snap_far_to: a point is far from any path.
  final List<String> warnings;

  /// Planned with hike: the alpine profile's much shorter way.
  final ({double distanceM, int sacGrade})? alpine;
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
      official = Official.of(j['official']),
      lines = [for (final l in j['lines'] as List? ?? const []) _line(l)];

  /// route or journey.
  final String kind, id, title, owner;

  /// Set for the official Wanderland routes.
  final Official? official;
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

/// A comment on a route or journey; replies have the comment's [parentId].
class Comment {
  Comment.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      parentId = j['parent_id'] as String?,
      authorUsername = j['author_username'] as String,
      authorName = j['author_name'] as String,
      body = j['body'] as String,
      createdAt = DateTime.parse(j['created_at'] as String),
      edited = j['edited_at'] != null,
      canEdit = j['can_edit'] as bool? ?? false,
      canDelete = j['can_delete'] as bool? ?? false;
  final String id;
  final String? parentId;
  final String authorUsername, authorName, body;
  final DateTime createdAt;
  final bool edited, canEdit, canDelete;
}

/// Likes and comments of a route or journey.
class Social {
  Social.fromJson(Map<String, dynamic> j)
    : likes = (j['likes'] as num).toInt(),
      liked = j['liked'] as bool,
      canComment = j['can_comment'] as bool,
      canModerate = j['can_moderate'] as bool,
      commentsEnabled = j['comments_enabled'] as bool,
      comments = [for (final c in j['comments'] as List) Comment.fromJson(c as Map<String, dynamic>)];
  final int likes;
  final bool liked, canComment, commentsEnabled;

  /// The owner: may switch comments off and delete others' comments.
  final bool canModerate;
  final List<Comment> comments;
}

/// A photo of a route or journey.
class Photo {
  Photo.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      caption = j['caption'] as String? ?? '',
      width = (j['width'] as num).toInt(),
      height = (j['height'] as num).toInt(),
      uploader = j['uploader'] as String? ?? '';
  final String id, caption;
  final int width, height;
  final String uploader;
}

/// Someone a route, journey or collection is shared with, or invited by
/// e-mail (then without an account yet).
class Grant {
  Grant.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      role = j['role'] as String,
      username = j['username'] as String? ?? '',
      displayName = j['display_name'] as String? ?? '',
      email = j['email'] as String? ?? '';

  /// viewer or editor.
  final String id, role;
  final String username, displayName, email;
}

/// A public route or journey of someone the user follows.
class FeedItem {
  FeedItem.fromJson(Map<String, dynamic> j)
    : kind = j['kind'] as String,
      id = j['id'] as String,
      title = j['title'] as String,
      owner = j['owner_username'] as String,
      ownerName = j['owner_name'] as String,
      publishedAt = DateTime.parse(j['published_at'] as String),
      distanceM = (j['distance_m'] as num).toDouble(),
      ascentM = (j['ascent_m'] as num).toDouble(),
      durationS = (j['duration_s'] as num).toInt(),
      sacGrade = (j['sac_grade'] as num).toInt(),
      sacMax = (j['sac_max'] as num).toInt(),
      stages = (j['stages'] as num?)?.toInt() ?? 0;

  /// route or journey.
  final String kind, id, title, owner, ownerName;
  final DateTime publishedAt;
  final double distanceM, ascentM;
  final int durationS, sacGrade, sacMax, stages;
}

/// A page of the feed; [next] continues with older items.
typedef FeedPage = ({List<FeedItem> items, DateTime? next});

/// A user's public profile.
class Profile {
  Profile.fromJson(Map<String, dynamic> j)
    : username = j['username'] as String,
      displayName = j['display_name'] as String,
      since = j['since'] as String,
      self = j['self'] as bool,
      followers = (j['followers'] as num).toInt(),
      following = (j['following'] as num).toInt(),
      followed = j['followed'] as bool,
      blocked = j['blocked'] as bool,
      friend = j['friend'] as String? ?? 'none',
      routes = [for (final r in j['routes'] as List) RouteSummary.fromJson(r as Map<String, dynamic>)],
      journeys = [for (final r in j['journeys'] as List) JourneySummary.fromJson(r as Map<String, dynamic>)];
  final String username, displayName;

  /// The month the account was made, e.g. 2026-09.
  final String since;

  /// This is the user's own profile.
  final bool self;
  final int followers, following;

  /// The user follows, or blocked, this one.
  final bool followed, blocked;

  /// none, requested (by the user), incoming (to the user) or friends.
  final String friend;
  final List<RouteSummary> routes;
  final List<JourneySummary> journeys;
}

/// Someone the user blocked.
class UserRef {
  UserRef.fromJson(Map<String, dynamic> j)
    : username = j['username'] as String,
      displayName = j['display_name'] as String;
  final String username, displayName;
}

/// A user with how one stands with them as friends: none, requested (by
/// one), incoming (to one) or friends.
class FriendRef {
  FriendRef.fromJson(Map<String, dynamic> j)
    : username = j['username'] as String,
      displayName = j['display_name'] as String,
      friend = j['friend'] as String;
  final String username, displayName, friend;
}

/// One's friends and the open requests.
typedef FriendLists = ({List<FriendRef> friends, List<FriendRef> incoming, List<FriendRef> outgoing});

/// When one hiked a route or journey (YYYY-MM-DD), and whether by one's own mark.
typedef DoneState = ({String? doneOn, bool marked});

/// A collection in lists.
class CollectionSummary {
  CollectionSummary.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      title = j['title'] as String,
      owner = j['owner_username'] as String,
      items = (j['items'] as num).toInt(),
      visibility = j['visibility'] as String;
  final String id, title, owner;
  final int items;
  final String visibility;
}

/// A route or journey in a collection.
class CollectionItem {
  CollectionItem.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      kind = j['kind'] as String,
      targetId = j['target_id'] as String,
      title = j['title'] as String,
      owner = j['owner_username'] as String,
      note = j['note'] as String? ?? '',
      distanceM = (j['distance_m'] as num).toDouble(),
      ascentM = (j['ascent_m'] as num).toDouble(),
      durationS = (j['duration_s'] as num).toInt(),
      sacGrade = (j['sac_grade'] as num).toInt(),
      sacMax = (j['sac_max'] as num).toInt(),
      stages = (j['stages'] as num?)?.toInt() ?? 0,
      lines = [for (final l in j['lines'] as List? ?? const []) _line(l)];

  /// The item in the collection; [targetId] the route or journey.
  final String id;

  /// route or journey.
  final String kind, targetId, title, owner, note;
  final double distanceM, ascentM;
  final int durationS, sacGrade, sacMax, stages;

  /// [lon, lat] per point; a journey has one line per routed stage.
  final List<List<List<double>>> lines;
}

/// A collection with its routes and journeys.
class Collection {
  Collection.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      title = j['title'] as String,
      description = j['description'] as String? ?? '',
      owner = j['owner_username'] as String,
      canEdit = j['can_edit'] as bool? ?? false,
      isOwner = j['role'] == 'owner',
      visibility = j['visibility'] as String? ?? 'private',
      shareToken = j['share_token'] as String?,
      items = [for (final i in j['item_list'] as List) CollectionItem.fromJson(i as Map<String, dynamic>)],
      hidden = (j['hidden'] as num?)?.toInt() ?? 0;
  final String id, title, description, owner;
  final bool canEdit, isOwner;

  /// private, unlisted or public; for the owner the link's token.
  final String visibility;
  final String? shareToken;
  final List<CollectionItem> items;

  /// How many items the user may not see.
  final int hidden;
}

/// What others shared with the user.
typedef Shared = ({List<RouteSummary> routes, List<JourneySummary> journeys, List<CollectionSummary> collections});

/// A public transport connection (`GET /connections`).
class Trip {
  Trip.fromJson(Map<String, dynamic> j)
    : start = DateTime.parse(j['start'] as String),
      end = DateTime.parse(j['end'] as String),
      transfers = (j['transfers'] as num).toInt(),
      legs = [for (final l in j['legs'] as List) TripLeg.fromJson(l as Map<String, dynamic>)];
  final DateTime start, end;
  final int transfers;
  final List<TripLeg> legs;
}

/// A ride or a walk of a [Trip].
class TripLeg {
  TripLeg.fromJson(Map<String, dynamic> j)
    : ride = j['kind'] == 'ride',
      from = j['from'] as String,
      to = j['to'] as String,
      line = j['line'] as String? ?? '',
      platform = j['platform'] as String? ?? '',
      departure = switch (j['departure']) {
        final String d => DateTime.parse(d),
        _ => null,
      },
      arrival = switch (j['arrival']) {
        final String d => DateTime.parse(d),
        _ => null,
      },
      delayMin = (j['delay_min'] as num?)?.toInt() ?? 0,
      walkMin = (j['duration_min'] as num?)?.toInt() ?? 0,
      track = _line(j['track']);

  /// A ride, else a walk of [walkMin] minutes.
  final bool ride;
  final String from, to, line, platform;
  final DateTime? departure, arrival;
  final int delayMin, walkMin;

  /// The way, when asked for: [lon, lat] per point.
  final List<List<double>> track;
}

/// Where the user sets off from and returns to by public transport.
class Home {
  Home.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      address = j['address'] as String? ?? '',
      lon = (j['lon'] as num).toDouble(),
      lat = (j['lat'] as num).toDouble();
  final String id, name, address;
  final double lon, lat;
}

/// A personal access token for AI assistants and alvyo-cli, without the
/// token itself: it only reads.
class AccessToken {
  AccessToken.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      createdAt = DateTime.parse(j['created_at'] as String),
      lastUsedAt = switch (j['last_used_at']) {
        final String at => DateTime.parse(at),
        _ => null,
      };
  final String id, name;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
}

/// Where a way starts or ends that is not a home: a place found by the search.
typedef TravelPlace = ({String name, double lon, double lat});

/// One direction of [Travel]: from or to a home ([homeId]) or another
/// [place], leaving after or arriving before [time] (HH:MM) on the day of the
/// hike.
class TravelWay {
  const TravelWay({this.homeId, this.place, required this.time, this.arrive = false});
  TravelWay.fromJson(Map<String, dynamic> j)
    : homeId = j['home_id'] as String?,
      place = switch (j['place']) {
        {'name': final String name, 'lon': final num lon, 'lat': final num lat} => (
          name: name,
          lon: lon.toDouble(),
          lat: lat.toDouble(),
        ),
        _ => null,
      },
      time = j['time'] as String,
      arrive = j['arrive'] as bool? ?? false;
  final String? homeId;
  final TravelPlace? place;
  final String time;
  final bool arrive;

  Map<String, dynamic> toJson() => {
    'home_id': ?homeId,
    if (place case final p?) 'place': {'name': p.name, 'lon': p.lon, 'lat': p.lat},
    'time': time,
    'arrive': arrive,
  };
}

/// The user's own way to the start of a journey or route ([to]) and back
/// from its end ([back]); null where none is chosen.
class Travel {
  const Travel({this.to, this.back});
  Travel.fromJson(Map<String, dynamic> j)
    : to = switch (j['to']) {
        final Map<String, dynamic> w => TravelWay.fromJson(w),
        _ => null,
      },
      back = switch (j['back']) {
        final Map<String, dynamic> w => TravelWay.fromJson(w),
        _ => null,
      };
  final TravelWay? to, back;

  Map<String, dynamic> toJson() => {'to': ?to?.toJson(), 'back': ?back?.toJson()};
}

/// Client of the Alvyo API. Logging in yields the session token, which
/// authenticates later calls as a Bearer token.
class Api {
  Api(String server, {this.token, this.userId, http.Client? client, Duration timeout = const Duration(seconds: 20)})
    : server = _normalized(server),
      _http = _Timeout(client ?? http.Client(), timeout);

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

  Uri _uri(String path) {
    final uri = Uri.parse('$server/api/v1$path');
    // An item opened from a link keeps the link's share token on every call.
    final id = RegExp(r'^/(?:routes|journeys|collections)/([0-9a-f-]{36})').firstMatch(path)?[1];
    final t = shareTokens[id];
    return t == null ? uri : uri.replace(queryParameters: {...uri.queryParameters, 't': t});
  }

  /// The share tokens of unlisted items opened from links, by item id.
  final shareTokens = <String, String>{};

  /// Calls for [id] carry [token] unless it has one already: a journey's
  /// stage routes its token, a collection's items the collection's pass.
  void shareTokenFor(String id, String? token) {
    if (token != null) shareTokens.putIfAbsent(id, () => token);
  }

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'User-Agent': 'alvyo-app',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  dynamic _decode(http.Response r) {
    if (r.statusCode >= 400) {
      var message = r.reasonPhrase ?? '';
      var errors = const <Map<String, dynamic>>[];
      try {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        message = body['detail'] as String? ?? message;
        errors = [for (final e in body['errors'] as List? ?? const []) e as Map<String, dynamic>];
      } on FormatException {
        // not JSON
      }
      throw ApiException(r.statusCode, message, errors);
    }
    return r.body.isEmpty ? null : jsonDecode(r.body);
  }

  Future<dynamic> _get(String path, [Map<String, Object>? query]) async {
    final uri = _uri(path);
    return _decode(
      await _http.get(
        query == null ? uri : uri.replace(queryParameters: {...uri.queryParameters, ...query}),
        headers: _headers,
      ),
    );
  }

  /// Logs in with e-mail or username and password.
  Future<Me> login(String login, String password) async {
    final r = await _http.post(
      _uri('/auth/login'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'login': login, 'password': password}),
    );
    return _loggedIn(r);
  }

  /// Logs in, or signs up, with the iOS app's own Apple sign-in: the
  /// tokens from the system's sheet and the nonce they were asked with.
  Future<Me> appleSignIn({
    required String identityToken,
    required String authorizationCode,
    required String nonce,
    required String name,
    required String locale,
  }) async {
    final r = await _http.post(
      _uri('/auth/oidc/apple/native'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'identity_token': identityToken,
        'authorization_code': authorizationCode,
        'nonce': nonce,
        if (name.isNotEmpty) 'name': name,
        'locale': locale,
      }),
    );
    return _loggedIn(r);
  }

  /// Takes the session from a login's answer.
  Me _loggedIn(http.Response r) {
    final body = _decode(r) as Map<String, dynamic>;
    final session = RegExp(r'alvyo_session=([^;,\s]+)').firstMatch(r.headers['set-cookie'] ?? '');
    if (session == null) throw ApiException(500, 'no session in the answer');
    token = session.group(1);
    final me = Me.fromJson(body['user'] as Map<String, dynamic>);
    userId = me.id;
    hikerPace.value = me.speedFactor;
    return me;
  }

  /// The ids of the sign-in providers the server offers, e.g. «apple».
  Future<List<String>> providers() async => [
    for (final p in ((await _get('/auth/providers')) as Map<String, dynamic>)['providers'] as List? ?? const [])
      (p as Map<String, dynamic>)['id'] as String,
  ];

  /// Signs up; the server answers the same for an address with an account
  /// and sends a link to confirm it (or a note how to log in).
  Future<void> signup({
    required String email,
    required String username,
    required String displayName,
    required String password,
    required String locale,
  }) => _send('POST', '/auth/signup', {
    'email': email,
    'username': username,
    'display_name': displayName,
    'password': password,
    'locale': locale,
  });

  /// Ends the account's other sessions (other phones and browsers).
  Future<void> logoutOthers() => _send('POST', '/auth/logout-others');

  Future<void> logout() async {
    await _http.post(_uri('/auth/logout'), headers: _headers);
    token = null;
  }

  Future<Me> me() async {
    final me = Me.fromJson(await _get('/me') as Map<String, dynamic>);
    hikerPace.value = me.speedFactor;
    return me;
  }

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

  /// Deletes a route of the user's own.
  Future<void> deleteRoute(String id) => _send('DELETE', '/routes/$id');

  /// Deletes a journey of the user's own with all its stages and routes.
  Future<void> deleteJourney(String id) => _send('DELETE', '/journeys/$id');

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

  /// The protected areas a route, or a journey's stages, cross, and the
  /// closed trails and shooting on the way.
  Future<Along> areas({String? routeId, String? journeyId}) async {
    final j =
        await _get(routeId != null ? '/routes/$routeId/areas' : '/journeys/$journeyId/areas') as Map<String, dynamic>;
    return (
      areas: [for (final a in j['areas'] as List) ProtectedArea.fromJson(a as Map<String, dynamic>)],
      notices: [for (final n in j['notices'] as List? ?? const []) Notice.fromJson(n as Map<String, dynamic>)],
    );
  }

  /// The snow along a route, or a journey's stages.
  Future<SnowAlong> snowAlong({String? routeId, String? journeyId}) async {
    final j = await _get(routeId != null ? '/routes/$routeId/snow' : '/journeys/$journeyId/snow');
    return SnowAlong.fromJson(j as Map<String, dynamic>);
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

  /// Summits, viewpoints, waterfalls, drinking water and shelters within
  /// 200 m of a route, in the order they come.
  Future<List<Poi>> pois(String routeId) async {
    final j = await _get('/routes/$routeId/pois') as Map<String, dynamic>;
    return [for (final p in j['pois'] as List) Poi.fromJson(p as Map<String, dynamic>)];
  }

  /// MeteoSwiss's forecast at a route's start, highest point and end.
  /// A [date] (YYYY-MM-DD) beyond the forecast brings the climate normals
  /// of its month.
  /// The rain on the map: the radar's last hour and the forecast.
  Future<PrecipTimeline> precip() async =>
      PrecipTimeline.fromJson(await _get('/weather/precip') as Map<String, dynamic>);

  /// The snow cover on the map: its day and tiles.
  Future<SnowCover> snow() async => SnowCover.fromJson(await _get('/weather/snow') as Map<String, dynamic>);

  Future<RouteWeather> routeWeather(String routeId, {String? date}) async =>
      RouteWeather.fromJson(await _get('/routes/$routeId/weather', {'date': ?date}) as Map<String, dynamic>);

  /// MeteoSwiss's forecast at each stage's highest point, for its planned day.
  Future<JourneyWeather> journeyWeather(String journeyId) async =>
      JourneyWeather.fromJson(await _get('/journeys/$journeyId/weather') as Map<String, dynamic>);

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
    final inCh = near != null && near.lon >= 5.7 && near.lon <= 10.7 && near.lat >= 45.65 && near.lat <= 47.95;
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

  /// The ways between [from] and [to] a leg can be dragged onto, the
  /// shortest first; [lon, lat] per point.
  Future<List<List<List<double>>>> alternatives(LonLat from, LonLat to, {String profile = 'hike'}) async {
    final j =
        await _send('POST', '/routing/alternatives', {
              'from': {'lon': from.lon, 'lat': from.lat},
              'to': {'lon': to.lon, 'lat': to.lat},
              'profile': profile,
            })
            as Map<String, dynamic>;
    return [
      for (final w in j['ways'] as List)
        [
          for (final p in w as List) [((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()],
        ],
    ];
  }

  /// What one reaches on foot from [from] within 2, 4 and 8 hours at one's
  /// pace, the smallest first; [profile] hike or alpine.
  /// The areas reached from [from] within 2, 4 and 8 hours; [back]: back
  /// at the start within them, each way timed as it goes.
  Future<List<ReachArea>> reach(LonLat from, {String profile = 'hike', bool back = false}) async {
    final j =
        await _send('POST', '/routing/reach', {
              'from': {'lon': from.lon, 'lat': from.lat},
              'profile': profile,
              if (back) 'back': true,
            })
            as Map<String, dynamic>;
    return [for (final a in j['areas'] as List) ReachArea.fromJson(a as Map<String, dynamic>)];
  }

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

  /// Who comes along on a journey and on which stages; 403 for those it is
  /// not shared with.
  Future<List<Person>> people(String journeyId) async => _people(await _get('/journeys/$journeyId/people'));

  /// Someone comes along (owner), by username or e-mail address, on all stages.
  Future<List<Person>> addPerson(String journeyId, String who) async => _people(
    await _send('POST', '/journeys/$journeyId/people', {
      if (who.contains('@')) 'email': who.trim() else 'username': who.trim().replaceFirst('@', ''),
    }),
  );

  /// The stages someone is on (owner and editors).
  Future<List<Person>> setPersonStages(String journeyId, String personId, List<String> stages) async =>
      _people(await _send('PUT', '/journeys/$journeyId/people/$personId', {'stages': stages}));

  /// Someone no longer comes along (owner); their access stays.
  Future<List<Person>> removePerson(String journeyId, String personId) async =>
      _people(await _send('DELETE', '/journeys/$journeyId/people/$personId'));

  List<Person> _people(dynamic j) => [
    for (final p in (j as Map<String, dynamic>)['people'] as List) Person.fromJson(p as Map<String, dynamic>),
  ];

  /// Whether reminders before the journey's start come by e-mail to the
  /// user, and the start (the first planned stage's day).
  Future<({bool on, DateTime? start})> reminders(String journeyId) async =>
      _reminders(await _get('/journeys/$journeyId/reminders'));

  Future<({bool on, DateTime? start})> setReminders(String journeyId, bool on) async =>
      _reminders(await _send('PUT', '/journeys/$journeyId/reminders', {'on': on}));

  ({bool on, DateTime? start}) _reminders(dynamic j) {
    final m = j as Map<String, dynamic>;
    return (
      on: m['on'] as bool,
      start: switch (m['start']) {
        final String d => DateTime.parse(d),
        _ => null,
      },
    );
  }

  /// Adds a stage at the end of a journey, without a route yet.
  Future<JourneyDetail> addStage(String journeyId) async =>
      JourneyDetail.fromJson(await _send('POST', '/journeys/$journeyId/stages', {}) as Map<String, dynamic>);

  /// Gives a stage without a route its planned route.
  Future<JourneyDetail> createStageRoute(
    String journeyId,
    String stageId, {
    required String profile,
    required List<Anchor> anchors,
    required List<Leg> legs,
  }) async => JourneyDetail.fromJson(
    await _send('POST', '/journeys/$journeyId/stages/$stageId/route', {
          'profile': profile,
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
  /// no way, or with [ApiException.fewestDays] when a day would be longer
  /// than [maxHours].
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
    String? official,
  }) async {
    final j =
        await _get('/discover', {
              'bbox': [view.west, view.south, view.east, view.north].map((v) => v.toStringAsFixed(4)).join(','),
              'kind': ?kind,
              'official': ?official,
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

  /// The user's own private copy of a route they can see, to change.
  Future<RouteDetail> copyRoute(String id) async =>
      RouteDetail.fromJson(await _send('POST', '/routes/$id/copy') as Map<String, dynamic>);

  /// The user's own private copy of a journey: its stages with their routes.
  Future<JourneyDetail> copyJourney(String id) async =>
      JourneyDetail.fromJson(await _send('POST', '/journeys/$id/copy') as Map<String, dynamic>);

  /// Has the server build the offline map of a route, unless it is built.
  Future<PackStatus> buildPack(String routeId) async => PackStatus.fromJson(
    _decode(await _http.post(_uri('/routes/$routeId/pack'), headers: _headers)) as Map<String, dynamic>,
  );

  Future<PackStatus> packStatus(String routeId) async =>
      PackStatus.fromJson(await _get('/routes/$routeId/pack') as Map<String, dynamic>);

  /// Starts the download of the pack for recognising mountains; 503 while
  /// the server still builds it.
  Future<http.StreamedResponse> peaksPack() async =>
      _http.send(http.Request('GET', _uri('/peaks/pack'))..headers.addAll(_headers));

  /// Starts the download of one layer of a route's offline map (PMTiles),
  /// [from] a byte offset to continue a broken off download (206 then).
  Future<http.StreamedResponse> packFile(String routeId, String layer, {int from = 0}) async {
    final req = http.Request('GET', _uri('/routes/$routeId/pack/$layer'))..headers.addAll(_headers);
    if (from > 0) req.headers['Range'] = 'bytes=$from-';
    final r = await _http.send(req);
    if (r.statusCode >= 400) _decode(await http.Response.fromStream(r));
    return r;
  }

  /// Changes the notification e-mails and their language.
  /// Changes the account's settings; [speedFactor] is the pace (hiking times
  /// as a multiple of the signposts').
  Future<Me> updateMe({
    String? locale,
    bool? notifyComments,
    bool? notifyFollows,
    double? speedFactor,
    bool? profilePublic,
  }) async {
    final me = Me.fromJson(
      await _send('PATCH', '/me', {
            'locale': ?locale,
            'notify_comments': ?notifyComments,
            'notify_follows': ?notifyFollows,
            'speed_factor': ?speedFactor,
            'profile_public': ?profilePublic,
          })
          as Map<String, dynamic>,
    );
    hikerPace.value = me.speedFactor;
    return me;
  }

  /// Deletes the account with all its routes; [password] confirms it
  /// (accounts without one need a recent login). 403 when it is wrong.
  Future<void> deleteMe({String? password}) => _send('DELETE', '/me', {'password': ?password});

  Future<Contact> addContact(String name, String email) async =>
      Contact.fromJson(await _send('POST', '/me/contacts', {'name': name, 'email': email}) as Map<String, dynamic>);

  Future<void> deleteContact(String id) => _send('DELETE', '/me/contacts/$id');

  Future<List<UserRef>> blocked() async {
    final j = await _get('/me/blocks') as Map<String, dynamic>;
    return [for (final u in j['users'] as List) UserRef.fromJson(u as Map<String, dynamic>)];
  }

  /// `routes` or `journeys`: both have the same endpoints for the rest.
  static String _kind(bool journey) => journey ? 'journeys' : 'routes';

  /// Changes a route's title, description, visibility or tags; fails with
  /// 412 when someone changed it since [version].
  Future<RouteDetail> updateRoute(String id, int version, Map<String, Object?> changes) async =>
      RouteDetail.fromJson(await _patch('/routes/$id', version, changes) as Map<String, dynamic>);

  Future<JourneyDetail> updateJourney(String id, int version, Map<String, Object?> changes) async =>
      JourneyDetail.fromJson(await _patch('/journeys/$id', version, changes) as Map<String, dynamic>);

  /// Changes a stage (title, planned_date, status, accommodation,
  /// accommodation_booked, notes, transfer_before); 412 as for routes.
  Future<JourneyDetail> updateStage(String journeyId, Stage stage, Map<String, Object?> changes) async =>
      JourneyDetail.fromJson(
        await _patch('/journeys/$journeyId/stages/${stage.id}', stage.version, changes) as Map<String, dynamic>,
      );

  Future<dynamic> _patch(String path, int version, Map<String, Object?> body) async {
    final r = await _http.patch(
      _uri(path),
      headers: {..._headers, 'Content-Type': 'application/json', 'If-Match': '"$version"'},
      body: jsonEncode(body),
    );
    return _decode(r);
  }

  /// The route or journey as a GPX file.
  Future<List<int>> gpx(String id, {bool journey = false}) async {
    final r = await _http.get(_uri('/${_kind(journey)}/$id/gpx'), headers: _headers);
    _decode(r.statusCode >= 400 ? r : http.Response('', 200));
    return r.bodyBytes;
  }

  Future<Social> social(String id, {bool journey = false}) async =>
      Social.fromJson(await _get('/${_kind(journey)}/$id/social') as Map<String, dynamic>);

  Future<Social> like(String id, bool on, {bool journey = false}) async =>
      Social.fromJson(await _send(on ? 'PUT' : 'DELETE', '/${_kind(journey)}/$id/like') as Map<String, dynamic>);

  /// A comment, or a reply to [parentId] (one level deep).
  Future<Social> comment(String id, String body, {String? parentId, bool journey = false}) async => Social.fromJson(
    await _send('POST', '/${_kind(journey)}/$id/comments', {'body': body, 'parent_id': ?parentId})
        as Map<String, dynamic>,
  );

  Future<Social> editComment(String id, String commentId, String body, {bool journey = false}) async => Social.fromJson(
    await _send('PATCH', '/${_kind(journey)}/$id/comments/$commentId', {'body': body}) as Map<String, dynamic>,
  );

  Future<Social> deleteComment(String id, String commentId, {bool journey = false}) async =>
      Social.fromJson(await _send('DELETE', '/${_kind(journey)}/$id/comments/$commentId') as Map<String, dynamic>);

  /// For the owner: comments on or off.
  Future<Social> setComments(String id, bool on, {bool journey = false}) async => Social.fromJson(
    await _send('PATCH', '/${_kind(journey)}/$id/social', {'comments_enabled': on}) as Map<String, dynamic>,
  );

  /// The photos in gallery order, and whether the user may add some.
  Future<({List<Photo> photos, bool canEdit})> photos(String id, {bool journey = false}) async =>
      _photos(await _get('/${_kind(journey)}/$id/photos'));

  ({List<Photo> photos, bool canEdit}) _photos(dynamic j) => (
    photos: [for (final p in (j as Map<String, dynamic>)['photos'] as List) Photo.fromJson(p as Map<String, dynamic>)],
    canEdit: j['can_edit'] as bool? ?? false,
  );

  /// Adds a photo (JPEG, PNG, WebP or HEIC). Fails with 413 when too big,
  /// 415 in another format, 422 when there are too many.
  /// Imports a GPX, KML, TCX or FIT file as a private route (its tracks
  /// joined); the routes made and the tracks skipped with why.
  Future<({List<({String id, String title})> routes, List<({String name, String reason})> skipped})> importFile(
    List<int> bytes,
    String filename,
  ) async {
    final req = http.MultipartRequest('POST', _uri('/imports'))
      ..headers.addAll(_headers)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final j = _decode(await http.Response.fromStream(await _http.send(req))) as Map<String, dynamic>;
    return (
      routes: [
        for (final r in j['routes'] as List? ?? const [])
          (id: (r as Map<String, dynamic>)['id'] as String, title: r['title'] as String),
      ],
      skipped: [
        for (final s in j['skipped'] as List? ?? const [])
          (name: (s as Map<String, dynamic>)['name'] as String, reason: s['reason'] as String),
      ],
    );
  }

  Future<({List<Photo> photos, bool canEdit})> addPhoto(
    String id,
    List<int> bytes,
    String filename, {
    String caption = '',
    bool journey = false,
  }) async {
    final req = http.MultipartRequest('POST', _uri('/${_kind(journey)}/$id/photos'))
      ..headers.addAll(_headers)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    if (caption.isNotEmpty) req.fields['caption'] = caption;
    return _photos(_decode(await http.Response.fromStream(await _http.send(req))));
  }

  Future<({List<Photo> photos, bool canEdit})> captionPhoto(
    String id,
    String photoId,
    String caption, {
    bool journey = false,
  }) async => _photos(await _send('PATCH', '/${_kind(journey)}/$id/photos/$photoId', {'caption': caption}));

  Future<({List<Photo> photos, bool canEdit})> deletePhoto(String id, String photoId, {bool journey = false}) async =>
      _photos(await _send('DELETE', '/${_kind(journey)}/$id/photos/$photoId'));

  /// The address of a photo file, [size] large or thumb; load it with [authHeaders].
  String photoUrl(String photoId, String size) => _uri('/photos/$photoId/$size').toString();

  Map<String, String> get authHeaders => {if (token != null) 'Authorization': 'Bearer $token'};

  /// For the owner: who the route, journey or collection is shared with.
  Future<List<Grant>> grants(String id, {bool journey = false, bool collection = false}) async =>
      _grants(await _get('/${_shared(journey, collection)}/$id/grants'));

  List<Grant> _grants(dynamic j) => [
    for (final g in (j as Map<String, dynamic>)['grants'] as List) Grant.fromJson(g as Map<String, dynamic>),
  ];

  /// Shares with an account (username) or an e-mail address, as viewer or editor.
  Future<List<Grant>> invite(
    String id,
    String who,
    String role, {
    bool journey = false,
    bool collection = false,
  }) async => _grants(
    await _send('POST', '/${_shared(journey, collection)}/$id/grants', {
      if (who.contains('@')) 'email': who else 'username': who,
      'role': role,
    }),
  );

  Future<List<Grant>> setGrantRole(
    String id,
    String grantId,
    String role, {
    bool journey = false,
    bool collection = false,
  }) async => _grants(await _send('PATCH', '/${_shared(journey, collection)}/$id/grants/$grantId', {'role': role}));

  Future<List<Grant>> removeGrant(String id, String grantId, {bool journey = false, bool collection = false}) async =>
      _grants(await _send('DELETE', '/${_shared(journey, collection)}/$id/grants/$grantId'));

  /// Replaces the share link; the old one stops working. Returns the new token.
  Future<String> rotateLink(String id, {bool journey = false, bool collection = false}) async =>
      ((await _send('POST', '/${_shared(journey, collection)}/$id/link/rotate')) as Map<String, dynamic>)['share_token']
          as String;

  static String _shared(bool journey, bool collection) => collection ? 'collections' : _kind(journey);

  /// Reports a bug: what happened, where ([place]), the app's version and
  /// a screenshot (PNG); the issue's address, if one was opened.
  Future<String?> reportBug({
    required String description,
    required String place,
    required String version,
    List<int>? screenshot,
  }) async {
    final j =
        await _send('POST', '/bug-reports', {
              'description': description,
              'place': place,
              'version': version,
              'platform': defaultTargetPlatform == TargetPlatform.android ? 'android' : 'ios',
              if (screenshot != null) 'screenshot': base64Encode(screenshot),
            })
            as Map<String, dynamic>;
    return j['issue_url'] as String?;
  }

  /// Reports a route, journey, comment, photo ([id]) or user ([username]) to
  /// the moderators; [reason] spam, offensive, dangerous or other.
  Future<void> report({required String kind, String? id, String? username, required String reason, String note = ''}) =>
      _send('POST', '/reports', {
        'kind': kind,
        'id': ?id,
        'username': ?username,
        'reason': reason,
        if (note.isNotEmpty) 'note': note,
      });

  /// Public routes and journeys of the people the user follows, newest
  /// first; [before] the previous page's next.
  Future<FeedPage> feed({DateTime? before}) async {
    final j =
        await _get('/feed', before == null ? null : {'before': before.toUtc().toIso8601String()})
            as Map<String, dynamic>;
    return (
      items: [for (final i in j['items'] as List) FeedItem.fromJson(i as Map<String, dynamic>)],
      next: switch (j['next']) {
        final String n => DateTime.parse(n),
        _ => null,
      },
    );
  }

  Future<Profile> profile(String username) async =>
      Profile.fromJson(await _get('/users/${Uri.encodeComponent(username)}') as Map<String, dynamic>);

  Future<void> follow(String username, bool on) =>
      _send(on ? 'PUT' : 'DELETE', '/users/${Uri.encodeComponent(username)}/follow');

  Future<void> block(String username, bool on) =>
      _send(on ? 'PUT' : 'DELETE', '/users/${Uri.encodeComponent(username)}/block');

  /// Public profiles by the start of the username or a part of the name.
  Future<List<FriendRef>> searchUsers(String q) async {
    final j = await _get('/users?q=${Uri.encodeQueryComponent(q)}') as Map<String, dynamic>;
    return [for (final u in j['users'] as List) FriendRef.fromJson(u as Map<String, dynamic>)];
  }

  /// Asks to be friends or accepts ([on]), or ends a friendship, withdraws
  /// or declines; the state afterwards.
  Future<String> friend(String username, bool on) async {
    final j =
        await _send(on ? 'PUT' : 'DELETE', '/users/${Uri.encodeComponent(username)}/friend') as Map<String, dynamic>;
    return j['friend'] as String;
  }

  Future<FriendLists> friends() async {
    final j = await _get('/me/friends') as Map<String, dynamic>;
    List<FriendRef> list(String k) => [for (final u in j[k] as List) FriendRef.fromJson(u as Map<String, dynamic>)];
    return (friends: list('friends'), incoming: list('incoming'), outgoing: list('outgoing'));
  }

  /// The token of one's invite link (/friends/invite/{token}); [renew]
  /// makes a new one, the old link stops working.
  Future<String> friendLink({bool renew = false}) async {
    final j = (renew ? await _send('POST', '/me/friend-link') : await _get('/me/friend-link')) as Map<String, dynamic>;
    return j['token'] as String;
  }

  /// Who sent the invite link with [token] (username, display name); an
  /// ApiException with status 404 if the link no longer holds.
  Future<({String username, String displayName})> friendInviter(String token) async {
    final j = await _get('/friend-invites/$token') as Map<String, dynamic>;
    return (username: j['username'] as String, displayName: j['display_name'] as String);
  }

  /// Become friends with whoever sent the invite link with [token].
  Future<void> acceptFriendInvite(String token) => _send('POST', '/friend-invites/$token');

  /// Marks a route or journey as hiked on [day] (today if null), or takes
  /// one's mark back.
  Future<DoneState> setDone(String id, {required bool journey, required bool on, DateTime? day}) async {
    final path = '/${_kind(journey)}/$id/done';
    final j =
        (on
                ? await _send('PUT', path, {if (day != null) 'done_on': day.toIso8601String().substring(0, 10)})
                : await _send('DELETE', path))
            as Map<String, dynamic>;
    return (doneOn: j['done_on'] as String?, marked: j['done_marked'] as bool? ?? false);
  }

  /// Routes, journeys and collections others shared with the user.
  Future<Shared> shared() async {
    final j = await _get('/shared') as Map<String, dynamic>;
    return (
      routes: [for (final r in j['routes'] as List) RouteSummary.fromJson(r as Map<String, dynamic>)],
      journeys: [for (final r in j['journeys'] as List) JourneySummary.fromJson(r as Map<String, dynamic>)],
      collections: [for (final c in j['collections'] as List) CollectionSummary.fromJson(c as Map<String, dynamic>)],
    );
  }

  /// The user's own collections.
  Future<List<CollectionSummary>> collections() async {
    final j = await _get('/collections') as Map<String, dynamic>;
    return [for (final c in j['collections'] as List) CollectionSummary.fromJson(c as Map<String, dynamic>)];
  }

  Future<Collection> collection(String id) async =>
      Collection.fromJson(await _get('/collections/$id') as Map<String, dynamic>);

  Future<Collection> createCollection(String title) async => Collection.fromJson(
    await _send('POST', '/collections', {'title': title, 'visibility': 'private'}) as Map<String, dynamic>,
  );

  Future<void> deleteCollection(String id) => _send('DELETE', '/collections/$id');

  /// Adds a route or journey the user can open.
  Future<Collection> addToCollection(String collectionId, String id, {bool journey = false}) async =>
      Collection.fromJson(
        await _send('POST', '/collections/$collectionId/items', {journey ? 'journey_id' : 'route_id': id})
            as Map<String, dynamic>,
      );

  Future<Collection> removeFromCollection(String collectionId, String itemId) async =>
      Collection.fromJson(await _send('DELETE', '/collections/$collectionId/items/$itemId') as Map<String, dynamic>);

  /// Public transport between two places on [day], leaving after [time]
  /// (HH:MM) or arriving before it. A place is a stop ([Place.ref]) or a
  /// position as lon,lat, named by [fromName] or [toName] in the walk to or
  /// from it; [lines] asks for the ways ([TripLeg.track]).
  Future<List<Trip>> connections(
    String from,
    String to,
    DateTime day, {
    String time = '08:00',
    bool arrive = false,
    String? fromName,
    String? toName,
    bool lines = false,
  }) async {
    final date =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final j =
        await _get('/connections', {
              'from': from,
              'to': to,
              'from_name': ?fromName,
              'to_name': ?toName,
              'date': date,
              'time': time,
              'arrive': '$arrive',
              if (lines) 'lines': 'true',
            })
            as Map<String, dynamic>;
    return [for (final t in j['trips'] as List) Trip.fromJson(t as Map<String, dynamic>)];
  }

  Future<List<Home>> homes() async {
    final j = await _get('/me/homes') as Map<String, dynamic>;
    return [for (final h in j['homes'] as List) Home.fromJson(h as Map<String, dynamic>)];
  }

  /// Adds a home (at most 5: 422).
  Future<Home> addHome(String name, String address, LonLat at) async => Home.fromJson(
    await _send('POST', '/me/homes', {'name': name, 'address': address, 'lon': at.lon, 'lat': at.lat})
        as Map<String, dynamic>,
  );

  Future<void> deleteHome(String id) => _send('DELETE', '/me/homes/$id');

  /// The personal access tokens, the newest first.
  Future<List<AccessToken>> accessTokens() async {
    final j = await _get('/me/tokens') as Map<String, dynamic>;
    return [for (final t in j['tokens'] as List) AccessToken.fromJson(t as Map<String, dynamic>)];
  }

  /// Creates an access token; the token itself comes with this answer only
  /// (at most 20: 422).
  Future<({AccessToken info, String token})> createAccessToken(String name) async {
    final j = await _send('POST', '/me/tokens', {'name': name}) as Map<String, dynamic>;
    return (info: AccessToken.fromJson(j), token: j['token'] as String);
  }

  Future<void> revokeAccessToken(String id) => _send('DELETE', '/me/tokens/$id');

  /// The user's own travel for a journey.
  Future<Travel> travel(String journeyId) async =>
      Travel.fromJson(await _get('/journeys/$journeyId/travel') as Map<String, dynamic>);

  Future<Travel> setTravel(String journeyId, Travel t) async =>
      Travel.fromJson(await _send('PUT', '/journeys/$journeyId/travel', t.toJson()) as Map<String, dynamic>);

  /// The user's own travel for a route.
  Future<Travel> routeTravel(String routeId) async =>
      Travel.fromJson(await _get('/routes/$routeId/travel') as Map<String, dynamic>);

  Future<Travel> setRouteTravel(String routeId, Travel t) async =>
      Travel.fromJson(await _send('PUT', '/routes/$routeId/travel', t.toJson()) as Map<String, dynamic>);

  /// The user's routes, journeys and recorded hikes (kind hike) in [view],
  /// with the filters of [discover].
  Future<({List<DiscoverItem> items, bool more})> myMap(
    Bbox view, {
    String? kind,
    int sacMax = 0,
    int? durationMin,
    int? durationMax,
    String? done, // planned or done (hiked); both if null
  }) async {
    final j =
        await _get('/me/map', {
              'done': ?done,
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
}

/// Gives up on an answer that does not start within [timeout]: with weak
/// reception at a trailhead a request could hang for minutes before the
/// app falls back to what it has offline. Downloads may take longer once
/// they have started.
class _Timeout extends http.BaseClient {
  _Timeout(this._inner, this.timeout);
  final http.Client _inner;
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _inner.send(request).timeout(timeout);

  @override
  void close() => _inner.close();
}
