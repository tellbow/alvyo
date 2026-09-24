import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'tracker.dart';

/// A hike being recorded. Positions are appended to a file as they come, so
/// nothing is lost when iOS stops the app; opening the route again resumes.
/// Finished hikes wait in `<root>/done/` until they are uploaded.
class Recording {
  Recording._(this.root, this.routeId, this.title, this.started);

  final Directory root;
  final String routeId, title;
  final DateTime started;

  static Future<Directory> defaultRoot() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/recordings');

  static File _meta(Directory root) => File('${root.path}/active.json');
  File get _fixes => File('${root.path}/active.jsonl');

  /// The recording in progress, if any.
  static Future<Recording?> active(Directory root) async {
    final meta = _meta(root);
    if (!await meta.exists()) return null;
    final m = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
    final r = Recording._(root, m['route_id'] as String, m['title'] as String, DateTime.parse(m['started'] as String));
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

  /// Starts recording a hike on a route; one at a time.
  static Future<Recording> start(
    Directory root, {
    required String routeId,
    required String title,
    DateTime? now,
  }) async {
    await root.create(recursive: true);
    final r = Recording._(root, routeId, title, (now ?? DateTime.now()).toUtc());
    try {
      await _meta(root).create(exclusive: true); // two starts at once: one wins
    } on FileSystemException {
      throw StateError('a hike is already being recorded');
    }
    await r._fixes.writeAsString('');
    await _meta(root).writeAsString(jsonEncode(r._metaJson()));
    return r;
  }

  Map<String, dynamic> _metaJson() => {'route_id': routeId, 'title': title, 'started': started.toIso8601String()};

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
