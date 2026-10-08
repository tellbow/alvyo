import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../api.dart';

/// A route saved on the phone with its offline map.
class SavedPack {
  SavedPack(this.key, this.files, this.route, this.turns);

  /// The server's pack key when saved; another key means the route changed.
  final String key;

  /// PMTiles file by layer.
  final Map<String, String> files;
  final RouteDetail route;

  /// For spoken navigation; null if they could not be had when saving.
  final List<Turn>? turns;
}

/// Offline maps of routes. The server builds them as PMTiles (national map
/// and hiking trails within 1 km, zoom 10–16); they are kept in
/// `<root>/route-<id>/` with a manifest holding the key and the route.
class PackStore {
  PackStore(this.root, {this.poll = const Duration(seconds: 1), this.maxPolls = 600});

  final Directory root;

  /// How often to ask the server while it builds.
  final Duration poll;

  /// How often the build is asked after (10 minutes at one a second): a
  /// build stuck on the server does not keep the app asking forever.
  final int maxPolls;

  static Future<PackStore> open() async =>
      PackStore(Directory('${(await getApplicationSupportDirectory()).path}/packs'));

  Directory _dir(String routeId) => Directory('${root.path}/route-$routeId');

  Future<SavedPack?> saved(String routeId) async {
    final dir = _dir(routeId);
    final manifest = File('${dir.path}/manifest.json');
    if (!await manifest.exists()) return null;
    final m = jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    return SavedPack(
      m['key'] as String,
      // Names only: the app's directory moves with app updates on iOS.
      {for (final e in (m['files'] as Map<String, dynamic>).entries) e.key: '${dir.path}/${e.value}'},
      RouteDetail.fromJson(m['route'] as Map<String, dynamic>),
      switch (m['turns']) {
        final List<dynamic> ts => [for (final t in ts) Turn.fromJson(t as Map<String, dynamic>)],
        _ => null,
      },
    );
  }

  /// All saved routes, by title.
  Future<List<RouteDetail>> savedRoutes() async {
    if (!await root.exists()) return [];
    final out = <RouteDetail>[];
    await for (final d in root.list()) {
      final name = d.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (d is Directory && name.startsWith('route-')) {
        final pack = await saved(name.substring('route-'.length));
        if (pack != null) out.add(pack.route);
      }
    }
    return out..sort((a, b) => a.title.compareTo(b.title));
  }

  File _journeyFile(String id) => File('${root.path}/journey-$id.json');

  /// Keeps a journey's stage list to open it offline; the stages' maps are
  /// saved as routes.
  Future<void> saveJourney(JourneyDetail j) async {
    await root.create(recursive: true);
    final file = _journeyFile(j.id);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(j.json));
    await tmp.rename(file.path);
  }

  /// Forgets a journey's stage list and the maps of its stages.
  Future<void> deleteJourney(JourneyDetail j) async {
    for (final s in j.stages) {
      if (s.routeId case final id?) await delete(id);
    }
    final file = _journeyFile(j.id);
    if (await file.exists()) await file.delete();
  }

  Future<JourneyDetail?> savedJourney(String id) async {
    final file = _journeyFile(id);
    if (!await file.exists()) return null;
    return JourneyDetail.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
  }

  /// All saved journeys, by title.
  Future<List<JourneyDetail>> savedJourneys() async {
    if (!await root.exists()) return [];
    final out = <JourneyDetail>[];
    await for (final f in root.list()) {
      final name = f.uri.pathSegments.last;
      if (f is File && name.startsWith('journey-') && name.endsWith('.json')) {
        out.add(JourneyDetail.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      }
    }
    return out..sort((a, b) => a.title.compareTo(b.title));
  }

  /// Has the server build the offline map of a route, then downloads it and
  /// replaces an older one. [progress] gets whether it downloads yet and the
  /// share done (0–1).
  Future<SavedPack> save(
    Api api,
    String routeId, {
    required void Function(bool downloading, double share) progress,
  }) async {
    final route = await api.route(routeId);
    List<Turn>? turns;
    try {
      turns = await api.turns(routeId);
    } on Exception {
      // saved without; navigating asks again when online
    }
    var st = await api.buildPack(routeId);
    var polls = 0;
    while (st.state != 'ready') {
      if (st.state == 'failed') throw ApiException(500, 'the offline map could not be built');
      if (++polls > maxPolls) throw ApiException(504, 'the offline map took too long to build');
      progress(false, st.total == 0 ? 0 : st.done / st.total);
      await Future<void>.delayed(poll);
      st = await api.packStatus(routeId);
      if (st.state == 'missing') st = await api.buildPack(routeId); // the server restarted or the route changed
    }

    final dir = _dir(routeId);
    await dir.create(recursive: true);
    await _excludeFromBackup();
    final total = st.files.fold<int>(0, (n, f) => n + f.bytes);
    var done = 0;
    for (final f in st.files) {
      if (!RegExp(r'^[\w.-]+\.pmtiles$').hasMatch(f.name)) throw ApiException(500, 'unexpected file ${f.name}');
      final file = File('${dir.path}/${f.name}');
      if (!await file.exists() || await file.length() != f.bytes) {
        // A broken off download of the same file (the name holds the key)
        // goes on where it stopped.
        final part = File('${file.path}.part');
        var have = await part.exists() ? await part.length() : 0;
        if (have > f.bytes) have = 0;
        if (have < f.bytes) {
          final resp = await api.packFile(routeId, f.layer, from: have);
          if (resp.statusCode != 206) have = 0; // the whole file after all
          done += have;
          final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
          try {
            await for (final chunk in resp.stream) {
              sink.add(chunk);
              done += chunk.length;
              progress(true, total == 0 ? 1 : done / total);
            }
          } finally {
            await sink.close();
          }
        } else {
          done += have;
        }
        // Not the map, e.g. the login page of a hut's Wi-Fi: start over
        // rather than resume after it.
        if (!await _isPmtiles(part)) {
          await part.delete();
          throw ApiException(500, 'the download of ${f.layer} is not a map');
        }
        if (await part.length() != f.bytes) throw ApiException(500, 'the download of ${f.layer} broke off');
        await part.rename(file.path);
      } else {
        done += f.bytes;
      }
    }

    final manifest = File('${dir.path}/manifest.json');
    final tmp = File('${manifest.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'key': st.key,
        'files': {for (final f in st.files) f.layer: f.name},
        'route': route.json,
        if (turns != null) 'turns': [for (final t in turns) t.toJson()],
      }),
    );
    await tmp.rename(manifest.path);
    // Files of an older pack go.
    final keep = {for (final f in st.files) f.name, 'manifest.json'};
    for (final e in await dir.list().toList()) {
      if (e is File && !keep.contains(e.uri.pathSegments.last)) await e.delete();
    }
    return (await saved(routeId))!;
  }

  /// Whether a file starts like a PMTiles archive (or like the start of one,
  /// when only a few bytes came).
  static Future<bool> _isPmtiles(File f) async {
    final head = await f.openRead(0, 7).fold<List<int>>([], (a, b) => a..addAll(b));
    return 'PMTiles'.startsWith(String.fromCharCodes(head));
  }

  /// Offline maps can be downloaded again: they stay out of iCloud backups
  /// (AppDelegate.swift).
  Future<void> _excludeFromBackup() async {
    if (!Platform.isIOS) return;
    try {
      await const MethodChannel('alvyo/backup').invokeMethod<bool>('exclude', root.path);
    } on PlatformException {
      // backed up after all; not worth failing the save
    }
  }

  Future<void> delete(String routeId) async {
    final dir = _dir(routeId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
