import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'l10n/app_localizations.dart';

/// The app's version, from the build (`--dart-define=ALVYO_VERSION=…`).
const appVersion = String.fromEnvironment('ALVYO_VERSION', defaultValue: 'dev');

/// What is open, as the website's address would say it: screens push theirs
/// («/routes/{id}») when they open and take it off when they close.
final openPlaces = <String>[];

/// Screens that show an item say so for bug reports.
mixin ReportsPlace<T extends StatefulWidget> on State<T> {
  String get place;

  @override
  void initState() {
    super.initState();
    openPlaces.add(place);
  }

  @override
  void dispose() {
    openPlaces.remove(place);
    super.dispose();
  }
}

/// Wraps the app: what it shows can be taken as a picture, and a small tab
/// at the right edge opens «Fehler melden» when [api] is signed in. The
/// maps (MapLibre's own views) stay empty in the picture.
class BugReportFrame extends StatefulWidget {
  const BugReportFrame({super.key, required this.api, required this.navigator, required this.child});
  final Api? Function() api;
  final GlobalKey<NavigatorState> navigator;
  final Widget child;

  @override
  State<BugReportFrame> createState() => _BugReportFrameState();
}

class _BugReportFrameState extends State<BugReportFrame> {
  final _boundary = GlobalKey();
  bool _taking = false;

  /// The window as shown, natively: the maps are platform views, which
  /// toImage leaves empty (all feedback screenshots until 1.3). Flutter's picture where
  /// that fails (tests, or no window).
  Future<Uint8List?> _screenshot() async {
    try {
      await WidgetsBinding.instance.endOfFrame; // the bug button hidden
      final jpeg = await const MethodChannel('alvyo/screenshot').invokeMethod<Uint8List>('window');
      if (jpeg != null) return jpeg;
    } on Object {
      // no channel
    }
    try {
      final r = _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (r == null) return null;
      final image = await r.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return png?.buffer.asUint8List();
    } on Object {
      return null;
    }
  }

  Future<void> _open(Api api) async {
    final context = widget.navigator.currentContext;
    if (context == null || _taking) return;
    setState(() => _taking = true);
    final shot = await _screenshot();
    if (mounted) setState(() => _taking = false);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BugSheet(api: api, screenshot: shot, place: openPlaces.lastOrNull ?? '/'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.api();
    return Stack(
      children: [
        RepaintBoundary(key: _boundary, child: widget.child),
        if (api != null && !_taking)
          Positioned(
            right: 0,
            top: MediaQuery.sizeOf(context).height * 0.45,
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHigh.withValues(alpha: 0.9),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
              elevation: 2,
              child: InkWell(
                key: const Key('bug-open'),
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                onTap: () => _open(api),
                child: Semantics(
                  button: true,
                  label: AppLocalizations.of(context).bugOpen,
                  child: const Padding(
                    padding: EdgeInsets.all(12), // 44 pt to tap
                    child: Icon(Icons.bug_report_outlined, size: 20),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BugSheet extends StatefulWidget {
  const _BugSheet({required this.api, required this.screenshot, required this.place});
  final Api api;
  final Uint8List? screenshot;
  final String place;

  @override
  State<_BugSheet> createState() => _BugSheetState();
}

class _BugSheetState extends State<_BugSheet> {
  final _text = TextEditingController();
  late bool _withShot = widget.screenshot != null;
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = AppLocalizations.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.api.reportBug(
        description: _text.text.trim(),
        place: widget.place,
        version: appVersion,
        screenshot: _withShot ? widget.screenshot : null,
      );
      if (mounted) setState(() => _sent = true);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e is ApiException && e.status == 429 ? t.bugBusy : t.bugFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: _sent
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(key: const Key('bug-sent'), t.bugSent),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: () => Navigator.pop(context), child: Text(t.close)),
                  ),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: [
                    Text(t.bugOpen, style: theme.textTheme.titleMedium),
                    TextField(
                      key: const Key('bug-text'),
                      controller: _text,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 4000,
                      decoration: InputDecoration(labelText: t.bugWhat, border: const OutlineInputBorder()),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (widget.screenshot case final shot?)
                      CheckboxListTile(
                        key: const Key('bug-with-shot'),
                        contentPadding: EdgeInsets.zero,
                        value: _withShot,
                        onChanged: (v) => setState(() => _withShot = v ?? false),
                        title: Text(t.bugWithScreenshot),
                        secondary: Image.memory(shot, height: 64, semanticLabel: t.bugScreenshotAlt),
                      ),
                    Text(
                      t.bugPrivacy(widget.place),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (_error case final e?) Text(e, style: TextStyle(color: theme.colorScheme.error)),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        key: const Key('bug-send'),
                        onPressed: _sending || _text.text.trim().isEmpty ? null : _send,
                        child: Text(t.bugSend),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
