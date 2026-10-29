import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/app_localizations.dart';
import 'route_screen.dart';
import 'watch_screen.dart';

/// «Importieren» in the profile (feedback issue 47): a file or the Apple
/// Watch's hikes, one place for both.
class ImportTile extends StatelessWidget {
  const ImportTile({super.key, required this.api, this.onImported, this.pickFile});
  final Api api;

  /// Tours were imported: the tours load again.
  final VoidCallback? onImported;

  /// For tests: stands in for the file picker.
  final Future<XFile?> Function()? pickFile;

  Future<void> _import(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final nav = Navigator.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(t.importTitle, style: Theme.of(context).textTheme.titleMedium)),
            ListTile(
              key: const Key('import-file'),
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(t.importFile),
              subtitle: Text(t.importFileHint),
              onTap: () => Navigator.pop(context, 'file'),
            ),
            ListTile(
              key: const Key('import-watch'),
              leading: const Icon(Icons.watch_outlined),
              title: Text(t.watchTitle),
              subtitle: Text(t.importWatchHint),
              onTap: () => Navigator.pop(context, 'watch'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'file' && context.mounted) await _importFile(context);
    if (choice == 'watch') {
      await nav.push(MaterialPageRoute<void>(builder: (_) => WatchScreen(api: api)));
      onImported?.call(); // imported hikes are routes now
    }
  }

  /// A GPX, KML, TCX or FIT file becomes a private route, opened at once.
  Future<void> _importFile(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    // Any file: the server says what it cannot read (iOS knows no GPX type).
    final file =
        await (pickFile ??
            () => openFile(
              acceptedTypeGroups: [
                XTypeGroup(
                  label: t.importFile,
                  extensions: const ['gpx', 'kml', 'tcx', 'fit'],
                  uniformTypeIdentifiers: const ['public.data'],
                ),
              ],
            ))();
    if (file == null) return;
    try {
      final result = await api.importFile(await file.readAsBytes(), file.name);
      onImported?.call();
      if (result.routes.firstOrNull case final r?) {
        await nav.push(
          MaterialPageRoute<void>(
            builder: (_) => RouteScreen(api: api, id: r.id, title: r.title),
          ),
        );
        return;
      }
      final reason = result.skipped.firstOrNull?.reason;
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (reason) {
            'outside' => t.watchOutside(t.watchReasonOutside),
            'short' => t.watchOutside(t.watchReasonShort),
            _ => t.errorServer,
          }),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.status == 422 ? t.importNotTrack : t.errorServer)));
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return ListTile(
      key: const Key('profile-import'),
      leading: const Icon(Icons.file_download_outlined),
      title: Text(t.importTitle),
      subtitle: Text(t.importFileHint),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _import(context),
    );
  }
}
