import 'package:flutter/foundation.dart';

import '../api.dart';
import 'packs.dart';

/// How far a save is: still being built on the server, or downloading.
typedef SaveProgress = ({bool downloading, double share});

/// Saves of offline maps that go on when the route screen is closed (while
/// the app runs), one per route. A save stopped by iOS or a lost connection
/// continues where it stopped the next time.
class PackDownloads {
  PackDownloads(this._store);

  static final instance = PackDownloads(PackStore.open());

  final Future<PackStore> _store;
  final _progress = <String, ValueNotifier<SaveProgress?>>{};
  final _jobs = <String, Future<SavedPack>>{};

  /// The progress of the route's save; null while none runs.
  ValueListenable<SaveProgress?> progress(String routeId) => _notifier(routeId);

  /// The route's save that is running, if any.
  Future<SavedPack>? running(String routeId) => _jobs[routeId];

  /// Saves the route's offline map, or joins the save already running.
  Future<SavedPack> save(Api api, String routeId) => _jobs[routeId] ??= _run(api, routeId);

  ValueNotifier<SaveProgress?> _notifier(String routeId) => _progress.putIfAbsent(routeId, () => ValueNotifier(null));

  Future<SavedPack> _run(Api api, String routeId) async {
    final p = _notifier(routeId)..value = (downloading: false, share: 0);
    try {
      return await (await _store).save(
        api,
        routeId,
        progress: (downloading, share) => p.value = (downloading: downloading, share: share),
      );
    } finally {
      p.value = null;
      _jobs.remove(routeId);
    }
  }
}
