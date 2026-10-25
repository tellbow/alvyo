import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'tracker.dart';

/// What becomes of the recording in progress when a hike starts.
enum Before {
  /// Nothing in progress.
  start,

  /// It is this route's: go on with it.
  resume,

  /// It is another route's: ask before ending it.
  ask,

  /// Another account's: keep it for that account, start anew.
  setAside,
}

/// A hike being recorded, on a route or without one. Positions are appended
/// to a file as they come, so nothing is lost when iOS stops the app; opening
/// the route (or the record button) again resumes. Finished hikes wait in
/// `<root>/done/` until they are uploaded.
class Recording {
  Recording._(this.root, this.routeId, this.title, this.started, this.owner);

  final Directory root;
  final String title;

  /// The route hiked; null when hiking without one.
  final String? routeId;
  final DateTime started;

  /// The account it is recorded for; it uploads only to that one. Null for
  /// recordings from before owners were kept, and when not known yet.
  final String? owner;

  /// The live share of this hike, if shared with contacts, and when it
  /// should end.
  String? liveId;
  DateTime? expectedEnd;

  /// Paused since then (no positions recorded), and the pauses before.
  DateTime? pausedAt;
  Duration paused = Duration.zero;

  /// The time hiked up to [now], without the pauses.
  Duration elapsed(DateTime now) {
    final since = pausedAt;
    final pausing = since != null && now.isAfter(since) ? now.difference(since) : Duration.zero;
    final d = now.difference(started) - paused - pausing;
    return d.isNegative ? Duration.zero : d;
  }

  Future<void> pause({DateTime? now}) async {
    if (pausedAt != null) return;
    pausedAt = (now ?? DateTime.now()).toUtc();
    await _writeMeta();
  }

  Future<void> resume({DateTime? now}) async {
    final since = pausedAt;
    if (since == null) return;
    paused += (now ?? DateTime.now()).difference(since);
    pausedAt = null;
    await _writeMeta();
  }

  /// Keeps the live share with the recording, for a resumed hike.
  Future<void> setLive(String id, DateTime end) async {
    liveId = id;
    expectedEnd = end;
    await _writeMeta();
  }

  static Future<Directory> defaultRoot() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/recordings');

  static File _meta(Directory root) => File('${root.path}/active.json');
  File get _fixes => File('${root.path}/active.jsonl');

  /// The recording in progress, if any.
  static Future<Recording?> active(Directory root) async {
    final meta = _meta(root);
    if (!await meta.exists()) return null;
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
    } on FormatException {
      // Stopped while starting (it is written whole after that): nothing
      // recorded yet, and it must not keep every later hike from starting.
      await meta.delete().catchError((_) => meta); // gone already: as well
      return null;
    }
    final r =
        Recording._(
            root,
            m['route_id'] as String?,
            m['title'] as String,
            DateTime.parse(m['started'] as String),
            m['owner'] as String?,
          )
          ..liveId = m['live_id'] as String?
          ..expectedEnd = switch (m['expected_end']) {
            final String e => DateTime.parse(e),
            _ => null,
          }
          ..pausedAt = switch (m['paused_at']) {
            final String p => DateTime.parse(p),
            _ => null,
          }
          ..paused = Duration(seconds: (m['paused_s'] as num?)?.round() ?? 0);
    await r._endLine();
    return r;
  }

  /// Ends a line cut off when the app was stopped while writing, so that the
  /// positions to come are not joined to it.
  Future<void> _endLine() async {
    if (!await _fixes.exists()) return;
    final f = await _fixes.open();
    final n = await f.length();
    var last = 10;
    if (n > 0) {
      await f.setPosition(n - 1);
      last = await f.readByte();
    }
    await f.close();
    if (last != 10) await _fixes.writeAsString('\n', mode: FileMode.append);
  }

  /// Starts recording a hike, on a route or without one; one at a time.
  static Future<Recording> start(
    Directory root, {
    String? routeId,
    required String title,
    String? owner,
    DateTime? now,
  }) async {
    await root.create(recursive: true);
    final r = Recording._(root, routeId, title, (now ?? DateTime.now()).toUtc(), owner);
    try {
      await _meta(root).create(exclusive: true); // two starts at once: one wins
    } on FileSystemException {
      throw StateError('a hike is already being recorded');
    }
    await r._fixes.writeAsString('');
    await r._writeMeta();
    return r;
  }

  /// Whole or not at all: the app can be stopped while writing.
  Future<void> _writeMeta() async {
    final tmp = File('${_meta(root).path}.tmp');
    await tmp.writeAsString(jsonEncode(_metaJson()));
    await tmp.rename(_meta(root).path);
  }

  Map<String, dynamic> _metaJson() => {
    'route_id': ?routeId,
    'title': title,
    'started': started.toIso8601String(),
    'owner': ?owner,
    'live_id': ?liveId,
    if (expectedEnd case final e?) 'expected_end': e.toUtc().toIso8601String(),
    if (pausedAt case final p?) 'paused_at': p.toUtc().toIso8601String(),
    if (paused > Duration.zero) 'paused_s': paused.inSeconds,
  };

  /// Whether it belongs to someone else than [user] (both known).
  bool ownedByOther(String? user) => owner != null && user != null && owner != user;

  /// What starting a hike on [routeId] (null: without a route) for [user]
  /// means for the recording in progress, [active].
  static Before before(Recording? active, String? routeId, String? user) {
    if (active == null) return Before.start;
    if (active.ownedByOther(user)) return Before.setAside;
    return active.routeId == routeId ? Before.resume : Before.ask;
  }

  /// Writes to a file, one after the other: appends that overlap would
  /// write at the same place.
  static final _writes = <String, Future<void>>{};

  Future<void> add(Fix fix) {
    final path = _fixes.path;
    final line = '${jsonEncode(fix.toJson())}\n';
    final done = (_writes[path] ?? Future.value()).then((_) async {
      await _fixes.writeAsString(line, mode: FileMode.append);
    });
    _writes[path] = done.catchError((_) {});
    return done;
  }

  /// The positions so far; a line cut off when the app was stopped while
  /// writing is left out.
  Future<List<Fix>> fixes() async {
    await _writes[_fixes.path];
    final out = <Fix>[];
    for (final l in await _fixes.readAsLines()) {
      try {
        if (l.isNotEmpty) out.add(Fix.fromJson(jsonDecode(l) as Map<String, dynamic>));
      } on FormatException {
        // cut off
      }
    }
    return out;
  }

  /// Ends the recording and keeps it for uploading; returns its file.
  Future<File> finish() async {
    final done = Directory('${root.path}/done');
    await done.create(recursive: true);
    final name = started.toIso8601String().replaceAll(':', '-');
    final out = File('${done.path}/$name.json');
    final tmp = File('${out.path}.tmp');
    await tmp.writeAsString(jsonEncode({..._metaJson(), 'fixes': await fixes()}));
    await tmp.rename(out.path);
    await _meta(root).delete();
    await _fixes.delete();
    return out;
  }
}
