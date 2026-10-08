import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../api.dart';
import '../navigation/uploads.dart';
import 'workouts.dart';

/// Why a workout did not become a route.
enum WatchFailure { noTrack, tooShort, outside, other }

/// Imports hikes from Apple Health as routes, like hikes recorded with the
/// app (the same id twice is one route), and remembers which.
class WatchImporter {
  WatchImporter(this.api, {WorkoutSource? source, File? importedFile})
    : source = source ?? HealthWorkouts(),
      _file0 = importedFile;

  final Api api;
  final WorkoutSource source;
  final File? _file0; // for tests
  Set<String>? _imported, _refused;

  Future<File> _file() async => _file0 ?? File('${(await getApplicationSupportDirectory()).path}/watch-imported.json');

  /// Workouts that cannot become routes (no track, too short, abroad): not
  /// tried again automatically on every start of the app.
  Future<File> _refusedFile() async => File((await _file()).path.replaceFirst(RegExp(r'\.json$'), '-refused.json'));

  static Future<Set<String>> _load(File file) async {
    if (!await file.exists()) return {};
    try {
      return {...(jsonDecode(await file.readAsString()) as List).cast<String>()};
    } on FormatException {
      return {}; // cut off: importing one again is fine (the same id)
    }
  }

  static Future<void> _save(File file, Set<String> ids) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(ids.toList()));
    await tmp.rename(file.path);
  }

  /// The workouts imported so far.
  Future<Set<String>> imported() async => _imported ??= await _load(await _file());

  Future<Set<String>> _refusedIds() async => _refused ??= await _load(await _refusedFile());

  /// Imports [w] titled [title]; null when done, else why not.
  Future<WatchFailure?> import(Workout w, String title) async {
    final failure = await _upload(w, title);
    if (failure == null) {
      await _save(await _file(), (await imported())..add(w.uuid));
    } else if (failure != WatchFailure.other) {
      await _save(await _refusedFile(), (await _refusedIds())..add(w.uuid));
    }
    return failure;
  }

  Future<WatchFailure?> _upload(Workout w, String title) async {
    final points = uploadPoints(await source.track(w));
    if (points.length < 2) return WatchFailure.noTrack;
    try {
      await api.uploadHike(id: 'watch-${w.uuid}', title: title, points: points);
    } on ApiException catch (e) {
      return failureOf(e);
    }
    return null;
  }

  /// Why the server refused a workout; its reasons are in English
  /// (hikeapi.go).
  static WatchFailure failureOf(ApiException e) => switch (e.message) {
    _ when e.status != 422 => WatchFailure.other,
    'the hike is too short' => WatchFailure.tooShort,
    final m when m.startsWith('the hike leaves') => WatchFailure.outside,
    _ => WatchFailure.other,
  };

  /// Imports the hikes and walks started after [since] not imported yet;
  /// how many became routes. Without Apple Health: none.
  Future<int> importNew(DateTime since, String Function(Workout w) title) async {
    if (!await source.authorize()) return 0;
    final done = await imported();
    final refused = await _refusedIds();
    var count = 0;
    for (final w in await source.recent(days: DateTime.now().difference(since).inDays + 1)) {
      if (w.start.isBefore(since) || done.contains(w.uuid) || refused.contains(w.uuid)) continue;
      if (await import(w, title(w)) == null) count++;
    }
    return count;
  }
}
