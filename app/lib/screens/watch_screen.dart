import 'dart:io';

import 'package:flutter/material.dart';
import 'wide.dart';

import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../watch/importer.dart';
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
  late final _importer = WatchImporter(widget.api, source: widget.source, importedFile: widget.importedFile);
  late final Future<List<Workout>?> _workouts = _load();
  Set<String> _imported = {};
  String? _busy;

  /// null: Apple Health is not available.
  Future<List<Workout>?> _load() async {
    _imported = await _importer.imported();
    if (!await _importer.source.authorize()) return null;
    return _importer.source.recent();
  }

  Future<void> _import(Workout w, {bool again = false}) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = w.uuid);
    try {
      final failure = await _importer.import(w, watchTitle(t, w), again: again);
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (failure) {
            null => t.watchImported,
            WatchFailure.noTrack => t.watchNoTrack,
            WatchFailure.tooShort => t.watchOutside(t.watchReasonShort),
            WatchFailure.outside => t.watchOutside(t.watchReasonOutside),
            WatchFailure.other => t.errorServer,
          }),
        ),
      );
    } on Exception {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// The route may have been deleted, renamed or changed: a new one, after
  /// asking.
  Future<void> _importAgain(Workout w) async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.watchAgainTitle),
        content: Text(t.watchAgainBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(t.watchImport)),
        ],
      ),
    );
    if (ok == true && mounted) await _import(w, again: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.watchTitle)),
      body: Readable(
        child: FutureBuilder(
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
                  title: Text(watchTitle(t, w)),
                  subtitle: Text(
                    [
                      if (w.distanceM != null) formatDistance(w.distanceM!),
                      formatDuration(w.end.difference(w.start).inSeconds),
                      w.source,
                    ].join(' · '),
                  ),
                  trailing: _busy == w.uuid
                      ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : done
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check, semanticLabel: t.watchImported),
                            TextButton(
                              onPressed: _busy == null ? () => _importAgain(w) : null,
                              child: Text(t.watchImportAgain),
                            ),
                          ],
                        )
                      : TextButton(onPressed: _busy == null ? () => _import(w) : null, child: Text(t.watchImport)),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// «Wanderung, 07.10.2026».
String watchTitle(AppLocalizations t, Workout w) => '${w.hiking ? t.watchHike : t.watchWalk}, ${formatDate(w.start)}';
