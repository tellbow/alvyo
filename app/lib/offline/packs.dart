import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../api.dart';

/// A route saved on the phone with its offline map.
class SavedPack {
  SavedPack(this.key, this.files, this.route);

  /// The server's pack key when saved; another key means the route changed.
  final String key;

  /// PMTiles file by layer.
  final Map<String, String> files;
  final RouteDetail route;
}

/// Offline maps of routes. The server builds them as PMTiles (national map
/// and hiking trails within 1 km, zoom 10–16); they are kept in
/// `<root>/route-<id>/` with a manifest holding the key and the route.
class PackStore {
  PackStore(this.root, {this.poll = const Duration(seconds: 1)});

  final Directory root;

  /// How often to ask the server while it builds.
  final Duration poll;

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

  /// Has the server build the offline map of a route, then downloads it and
  /// replaces an older one. [progress] gets whether it downloads yet and the
  /// share done (0–1).
  Future<SavedPack> save(
    Api api,
    String routeId, {
    required void Function(bool downloading, double share) progress,
  }) async {
    final route = await api.route(routeId);
    var st = await api.buildPack(routeId);
    while (st.state != 'ready') {
      if (st.state == 'failed') throw ApiException(500, 'the offline map could not be built');
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

  /// Offline maps can be downloaded again: they stay out of iCloud backups
  /// (AppDelegate.swift).
  Future<void> _excludeFromBackup() async {
    if (!Platform.isIOS) return;
    try {
      await const MethodChannel('odysgeh/backup').invokeMethod<bool>('exclude', root.path);
    } on PlatformException {
      // backed up after all; not worth failing the save
    }
  }

  Future<void> delete(String routeId) async {
    final dir = _dir(routeId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
