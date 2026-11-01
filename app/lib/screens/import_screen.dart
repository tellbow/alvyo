import 'package:flutter/material.dart';

import '../api.dart';
import '../elevation_profile.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import 'journey_screen.dart';
import 'route_screen.dart';
import 'stage_split_screen.dart';

/// What a file holds, on a map with its elevation profile, before anything
/// is saved, and how to take it (feedback issue 47), as on the website.
class ImportScreen extends StatefulWidget {
  const ImportScreen({
    super.key,
    required this.api,
    required this.bytes,
    required this.filename,
    this.onImported,
    this.showMap = true,
  });
  final Api api;
  final List<int> bytes;
  final String filename;

  /// Widget tests have no native map.
  final bool showMap;

  /// Tours were imported: the tours load again.
  final VoidCallback? onImported;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

enum _Mode { route, routes, journey, stages }

class _ImportScreenState extends State<ImportScreen> {
  ImportPreview? _preview;
  _Mode _mode = _Mode.route;
  bool _busy = true;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await widget.api.previewImport(widget.bytes, widget.filename);
      if (mounted) {
        setState(() {
          _preview = p;
          _busy = false;
        });
      }
    } on Object catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      setState(() {
        _busy = false;
        _problem = e is ApiException && e.status == 422 ? t.importNotTrack : t.errorServer;
      });
    }
  }

  List<ImportTrack> get _inside => _preview!.tracks.where((t) => t.inside && t.line.length > 1).toList();

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    final nav = Navigator.of(context);
    final inside = _inside;
    if (_mode == _Mode.stages) {
      final nights = _preview!.tracks.fold(0, (n, tr) => n + tr.nights);
      await nav.push(
        MaterialPageRoute<void>(
          builder: (_) => StageSplitScreen(
            api: widget.api,
            line: [for (final tr in inside) ...tr.line],
            title: _preview!.tracks.first.name,
            durationS: 0,
            nights: nights,
            showMap: widget.showMap,
            onSaved: widget.onImported,
            propose: (days, ends) => widget.api.importStages(
              widget.bytes,
              widget.filename,
              // As many days as a recording has: split at its nights.
              days: ends == null && days == nights + 1 ? null : days,
              ends: ends,
            ),
          ),
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final result = await widget.api.importFile(widget.bytes, widget.filename, mode: _mode.name);
      widget.onImported?.call();
      if (!mounted) return;
      if (result.journeyId case final id? when result.skipped.isEmpty) {
        await nav.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => JourneyScreen(api: widget.api, id: id, title: _preview!.tracks.first.name),
          ),
        );
        return;
      }
      if (result.routes.length == 1 && result.skipped.isEmpty) {
        final r = result.routes.first;
        await nav.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => RouteScreen(api: widget.api, id: r.id, title: r.title),
          ),
        );
        return;
      }
      final reason = result.skipped.firstOrNull?.reason;
      setState(() {
        _busy = false;
        _problem = switch (reason) {
          'outside' => t.watchOutside(t.watchReasonOutside),
          'short' => t.watchOutside(t.watchReasonShort),
          null => null,
          _ => t.errorServer,
        };
      });
      if (reason == null) nav.pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _problem = e is ApiException && e.status == 422 ? t.importNotTrack : t.errorServer;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final p = _preview;
    final inside = p == null ? const <ImportTrack>[] : _inside;
    final line = [for (final tr in inside) ...tr.line];
    final several = (p?.tracks.length ?? 0) > 1;
    return Scaffold(
      appBar: AppBar(title: Text(t.importTitle)),
      body: Column(
        children: [
          if (widget.showMap && inside.isNotEmpty)
            SizedBox(
              height: 240,
              child: StageMap(api: widget.api, lines: [for (final tr in inside) tr.line]),
            ),
          if (_busy) const LinearProgressIndicator(key: Key('import-busy')),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (line.any((c) => c[2] != 0)) ElevationProfile.ofLine(line),
                for (final (i, tr) in (p?.tracks ?? const <ImportTrack>[]).indexed)
                  ListTile(
                    key: Key('import-track-$i'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(tr.name),
                    subtitle: tr.inside ? null : Text(t.importOutside),
                    trailing: Text(formatDistance(tr.distanceM)),
                  ),
                if (p != null && inside.isEmpty) Text(key: const Key('import-none'), t.importOutside),
                if (inside.isNotEmpty) ...[
                  RadioGroup<_Mode>(
                    groupValue: _mode,
                    onChanged: (m) => setState(() => _mode = m ?? _mode),
                    child: Column(
                      children: [
                        RadioListTile(
                          key: const Key('import-mode-route'),
                          contentPadding: EdgeInsets.zero,
                          value: _Mode.route,
                          title: Text(several ? t.importAsJoined : t.importAsRoute),
                        ),
                        if (several) ...[
                          RadioListTile(
                            key: const Key('import-mode-routes'),
                            contentPadding: EdgeInsets.zero,
                            value: _Mode.routes,
                            title: Text(t.importAsRoutes),
                          ),
                          RadioListTile(
                            key: const Key('import-mode-journey'),
                            contentPadding: EdgeInsets.zero,
                            value: _Mode.journey,
                            title: Text(t.importAsJourney),
                          ),
                        ],
                        RadioListTile(
                          key: const Key('import-mode-stages'),
                          contentPadding: EdgeInsets.zero,
                          value: _Mode.stages,
                          title: Text(t.routeSplit),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const Key('import-submit'),
                    onPressed: _busy ? null : _submit,
                    child: Text(_mode == _Mode.stages ? t.routeSplit : t.importTitle),
                  ),
                ],
                if (_problem case final problem?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      key: const Key('import-problem'),
                      problem,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
