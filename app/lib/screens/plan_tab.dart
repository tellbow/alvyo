import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/app_localizations.dart';
import 'journey_plan_screen.dart';
import 'planner_screen.dart';
import 'reach_screen.dart';
import 'route_screen.dart';
import 'tab_header.dart';
import 'watch_screen.dart';

/// The kinds of planning.
enum PlanMode { day, multi, reach }

/// Planen (requirement 69): one place for a day's route, a journey of
/// several days and how far one gets; «Importieren» brings in tours.
class PlanTab extends StatefulWidget {
  const PlanTab({super.key, required this.api, this.onSaved, this.modes, this.pickFile});
  final Api api;

  /// A route or journey was saved: the tours load again.
  final VoidCallback? onSaved;

  /// For tests: stands in for the planning screens (MapLibre).
  final Widget Function(PlanMode mode, VoidCallback saved)? modes;

  /// For tests: stands in for the file picker.
  final Future<XFile?> Function()? pickFile;

  @override
  State<PlanTab> createState() => PlanTabState();
}

class PlanTabState extends State<PlanTab> {
  PlanMode _mode = PlanMode.day;

  /// Counts the plans: a new one after each save.
  int _plan = 0;

  /// Shows a mode (from Entdecken).
  void show(PlanMode mode) => setState(() => _mode = mode);

  void _saved() {
    widget.onSaved?.call();
    if (mounted) setState(() => _plan++);
  }

  Future<void> _import() async {
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
    if (choice == 'file') await _importFile();
    if (choice == 'watch') {
      await nav.push(MaterialPageRoute<void>(builder: (_) => WatchScreen(api: widget.api)));
      widget.onSaved?.call(); // imported hikes are routes now
    }
  }

  /// A GPX, KML, TCX or FIT file becomes a private route, opened at once.
  Future<void> _importFile() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    // Any file: the server says what it cannot read (iOS knows no GPX type).
    final file =
        await (widget.pickFile ??
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
      final result = await widget.api.importFile(await file.readAsBytes(), file.name);
      widget.onSaved?.call();
      if (result.routes.firstOrNull case final r?) {
        await nav.push(
          MaterialPageRoute<void>(
            builder: (_) => RouteScreen(api: widget.api, id: r.id, title: r.title),
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
    final key = ValueKey('${_mode.name}-$_plan');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabHeader(
          t.barPlan,
          action: HeaderAction(
            key: const Key('plan-import'),
            icon: Icons.file_download_outlined,
            label: t.importAction,
            onPressed: _import,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: SegmentedButton<PlanMode>(
            key: const Key('plan-mode'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: PlanMode.day,
                label: Text(t.planDay, key: const Key('plan-mode-day')),
              ),
              ButtonSegment(
                value: PlanMode.multi,
                label: Text(t.planMulti, key: const Key('plan-mode-multi')),
              ),
              ButtonSegment(
                value: PlanMode.reach,
                label: Text(t.planReach, key: const Key('plan-mode-reach')),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (v) => setState(() => _mode = v.first),
          ),
        ),
        Expanded(
          // Above the floating bar: the home screen's Scaffold passes its
          // height (with the phone's bottom edge) as padding.
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child:
                  widget.modes?.call(_mode, _saved) ??
                  switch (_mode) {
                    PlanMode.day => PlannerScreen(key: key, api: widget.api, embedded: true, onSaved: _saved),
                    PlanMode.multi => JourneyPlanScreen(key: key, api: widget.api, embedded: true, onSaved: _saved),
                    PlanMode.reach => ReachScreen(key: key, api: widget.api, embedded: true),
                  },
            ),
          ),
        ),
      ],
    );
  }
}
