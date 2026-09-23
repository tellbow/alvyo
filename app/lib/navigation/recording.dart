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
    return Recording._(root, m['route_id'] as String, m['title'] as String, DateTime.parse(m['started'] as String));
  }

  /// Starts recording a hike on a route; one at a time.
  static Future<Recording> start(
    Directory root, {
    required String routeId,
    required String title,
    DateTime? now,
  }) async {
    if (await active(root) != null) throw StateError('a hike is already being recorded');
    await root.create(recursive: true);
    final r = Recording._(root, routeId, title, (now ?? DateTime.now()).toUtc());
    await r._fixes.writeAsString('');
    await _meta(root).writeAsString(jsonEncode(r._metaJson()));
    return r;
  }

  Map<String, dynamic> _metaJson() => {'route_id': routeId, 'title': title, 'started': started.toIso8601String()};

  Future<void> add(Fix fix) => _fixes.writeAsString('${jsonEncode(fix.toJson())}\n', mode: FileMode.append);

  Future<List<Fix>> fixes() async => [
    for (final l in await _fixes.readAsLines())
      if (l.isNotEmpty) Fix.fromJson(jsonDecode(l) as Map<String, dynamic>),
  ];

  /// Ends the recording and keeps it for uploading; returns its file.
  Future<File> finish() async {
    final done = Directory('${root.path}/done');
    await done.create(recursive: true);
    final name = started.toIso8601String().replaceAll(':', '-');
    final out = File('${done.path}/$name.json');
    await out.writeAsString(jsonEncode({..._metaJson(), 'fixes': await fixes()}));
    await _fixes.delete();
    await _meta(root).delete();
    return out;
  }
}
