import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../navigation/uploads.dart';
import '../watch/workouts.dart';

/// Hikes recorded with the Apple Watch's Workout app, from Apple Health: each
/// can be imported as a route, like a hike recorded with this app.
class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key, required this.api, this.source, this.importedFile});
  final Api api;

  /// For tests: instead of Apple Health, and where imports are remembered.
  final WorkoutSource? source;
  final File? importedFile;

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  late final WorkoutSource _source = widget.source ?? HealthWorkouts();
  late final Future<List<Workout>?> _workouts = _load();
  Set<String> _imported = {};
  String? _busy;

  Future<File> _importedFile() async =>
      widget.importedFile ?? File('${(await getApplicationSupportDirectory()).path}/watch-imported.json');

  /// null: Apple Health is not available.
  Future<List<Workout>?> _load() async {
    final file = await _importedFile();
    if (await file.exists()) {
      _imported = {...(jsonDecode(await file.readAsString()) as List).cast<String>()};
    }
    if (!await _source.authorize()) return null;
    return _source.recent();
  }

  String _title(AppLocalizations t, Workout w) => '${w.hiking ? t.watchHike : t.watchWalk}, ${formatDate(w.start)}';

  Future<void> _import(Workout w) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = w.uuid);
    try {
      final points = uploadPoints(await _source.track(w));
      if (points.length < 2) {
        messenger.showSnackBar(SnackBar(content: Text(t.watchNoTrack)));
        return;
      }
      await widget.api.uploadHike(id: 'watch-${w.uuid}', title: _title(t, w), points: points);
      _imported.add(w.uuid);
      await (await _importedFile()).writeAsString(jsonEncode(_imported.toList()));
      messenger.showSnackBar(SnackBar(content: Text(t.watchImported)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.status == 422 ? t.watchOutside(e.message) : t.errorServer)));
    } on Exception {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.watchTitle)),
      body: FutureBuilder(
        future: _workouts,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final workouts = snap.data;
          final message = snap.hasError || workouts == null
              ? t.watchUnavailable
              : workouts.isEmpty
              ? t.watchEmpty
              : null;
          if (message != null) {
            return Padding(padding: const EdgeInsets.all(16), child: Text(message));
          }
          return ListView.separated(
            itemCount: workouts!.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final w = workouts[i];
              final done = _imported.contains(w.uuid);
              return ListTile(
                key: Key('workout-${w.uuid}'),
                title: Text(_title(t, w)),
                subtitle: Text(
                  [
                    if (w.distanceM != null) formatDistance(w.distanceM!),
                    formatDuration(w.end.difference(w.start).inSeconds),
                    w.source,
                  ].join(' · '),
                ),
                trailing: done
                    ? Icon(Icons.check, semanticLabel: t.watchImported)
                    : _busy == w.uuid
                    ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton(onPressed: _busy == null ? () => _import(w) : null, child: Text(t.watchImport)),
              );
            },
          );
        },
      ),
    );
  }
}
