import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../l10n/app_localizations.dart';
import '../navigation/gps.dart';
import '../peaks/pack.dart';
import '../peaks/projection.dart';
import '../peaks/store.dart';
import '../peaks/view.dart';

/// Recognising mountains (requirement 68): the camera's picture with the
/// summits in sight named, also without reception once the pack is saved.
class PeaksScreen extends StatefulWidget {
  const PeaksScreen({super.key, required this.api, this.store, this.position, this.motion, this.camera});
  final Api api;

  /// For tests: the saved pack, where one stands, the attitude and the
  /// camera's picture.
  final Future<PeakStore>? store;
  final Future<({double lon, double lat})?> Function()? position;
  final Stream<CameraPose>? motion;
  final Widget? camera;

  @override
  State<PeaksScreen> createState() => _PeaksScreenState();
}

/// The attitude from the native side (PeakCamera.swift), smoothed a little.
Stream<CameraPose> peakMotion() {
  List<double>? smooth;
  return const EventChannel('alvyo/peak-motion').receiveBroadcastStream().map((e) {
    final m = e as Map<Object?, Object?>;
    final raw = [for (final v in m['m']! as List<Object?>) (v! as num).toDouble()];
    final s = smooth == null ? raw : [for (var i = 0; i < 9; i++) smooth![i] * 0.6 + raw[i] * 0.4];
    smooth = s;
    return CameraPose(
      s,
      fov: (m['fov']! as num).toDouble(),
      aspect: (m['aspect']! as num).toDouble(),
      accuracy: (m['accuracy']! as num).toInt(),
    );
  });
}

class _PeaksScreenState extends State<PeaksScreen> {
  PeakStore? _store;
  PeakPack? _pack;
  PeakView? _view;
  CameraPose? _pose;
  StreamSubscription<CameraPose>? _motion;
  bool _noPosition = false, _noCompass = false, _noCamera = false, _failed = false;
  double? _progress; // while downloading: 0…1, or 0 while the server builds it

  /// The alignment by dragging, in degrees.
  double _dAz = 0, _dEl = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _open();
    if (widget.camera == null && defaultTargetPlatform == TargetPlatform.iOS) _askCamera();
    _motion = (widget.motion ?? peakMotion()).listen(
      (p) {
        if (mounted) setState(() => _pose = p);
      },
      onError: (Object _) {
        if (mounted) setState(() => _noCompass = true);
      },
    );
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([]);
    _motion?.cancel();
    super.dispose();
  }

  Future<void> _open() async {
    final store = await (widget.store ?? PeakStore.open());
    if (!mounted) return;
    setState(() => _store = store);
    if (store.saved) await _load();
  }

  /// Without access the picture stays black: say why.
  Future<void> _askCamera() async {
    final granted = await const MethodChannel('alvyo/camera').invokeMethod<bool>('access') ?? true;
    if (mounted && !granted) setState(() => _noCamera = true);
  }

  Future<void> _load() async {
    final pack = await _store!.load();
    if (!mounted) return;
    setState(() => _pack = pack);
    final at =
        await (widget.position ??
            () async => await locationAllowed() ? await knownPosition(maxAge: const Duration(minutes: 2)) : null)();
    if (!mounted) return;
    if (at == null) {
      setState(() => _noPosition = true);
      return;
    }
    final view = await computeViewInBackground(pack, at.lon, at.lat);
    if (mounted) setState(() => _view = view);
  }

  Future<void> _download() async {
    setState(() {
      _progress = 0;
      _failed = false;
    });
    try {
      await _store!.download(
        widget.api,
        progress: (got, total) {
          if (mounted && total > 0) setState(() => _progress = got / total);
        },
      );
      if (!mounted) return;
      setState(() => _progress = null);
      await _load();
    } on Object {
      if (mounted) {
        setState(() {
          _progress = null;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final store = _store;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(t.peaksTitle)),
      body: switch (store) {
        null => const Center(child: CircularProgressIndicator()),
        _ when !store.saved || _progress != null => _downloadCard(t),
        _ => _camera(t),
      },
    );
  }

  Widget _downloadCard(AppLocalizations t) => Center(
    child: Card(
      key: const Key('peaks-download'),
      margin: const EdgeInsets.all(24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.peaksDownloadText),
            const SizedBox(height: 16),
            if (_progress case final p?) ...[
              LinearProgressIndicator(value: p > 0 ? p : null),
              const SizedBox(height: 8),
              Text(p > 0 ? '${(p * 100).round()} %' : t.peaksPreparing, textAlign: TextAlign.center),
            ] else ...[
              if (_failed) Text(t.peaksDownloadFailed, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              FilledButton(key: const Key('peaks-download-start'), onPressed: _download, child: Text(t.peaksDownload)),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _camera(AppLocalizations t) {
    final pose = _pose, view = _view;
    final centre = pose?.centre;
    final message = switch (null) {
      _ when _noCamera => t.peaksNoCamera,
      _ when _noCompass => t.peaksNoCompass,
      _ when _noPosition => t.peaksNoPosition,
      _ when _pack == null || view == null => t.peaksComputing,
      _ when pose != null && pose.accuracy < 1 => t.peaksCompass,
      _ => null,
    };
    return LayoutBuilder(
      builder: (context, size) {
        final screen = Size(size.maxWidth, size.maxHeight);
        return GestureDetector(
          onPanUpdate: pose == null
              ? null
              : (d) => setState(() {
                  final perPx = pose.fov / max(screen.height, screen.width * pose.aspect);
                  _dAz += d.delta.dx * perPx;
                  _dEl -= d.delta.dy * perPx;
                }),
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.camera ??
                  (defaultTargetPlatform == TargetPlatform.iOS
                      ? const UiKitView(viewType: 'alvyo/peak-camera')
                      : const ColoredBox(color: Colors.black)),
              if (pose != null && view != null)
                CustomPaint(
                  key: const Key('peaks-overlay'),
                  painter: PeaksPainter(view, pose, _dAz, _dEl, Theme.of(context).textTheme.bodySmall!),
                ),
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Column(
                  children: [
                    if (centre != null)
                      _chip(
                        t.peaksDirection(
                          ((centre.azimuth - _dAz + 360) % 360).round(),
                          (centre.elevation - _dEl).round(),
                        ),
                        key: const Key('peaks-direction'),
                      ),
                    if (message != null) ...[
                      const SizedBox(height: 8),
                      _chip(message, key: const Key('peaks-message')),
                    ],
                  ],
                ),
              ),
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    Expanded(child: _chip(t.peaksAlign)),
                    if (_dAz != 0 || _dEl != 0) ...[
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        key: const Key('peaks-reset'),
                        onPressed: () => setState(() => _dAz = _dEl = 0),
                        child: Text(t.peaksReset),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String text, {Key? key}) => DecoratedBox(
    key: key,
    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

/// The skyline and the named summits over the camera's picture, moved by
/// the alignment [dAz], [dEl] (degrees).
class PeaksPainter extends CustomPainter {
  PeaksPainter(this.view, this.pose, this.dAz, this.dEl, this.text);
  final PeakView view;
  final CameraPose pose;
  final double dAz, dEl;
  final TextStyle text;

  /// At most this many labels.
  static const maxLabels = 30;

  Offset? _at(double az, double el, Size size) => pose.project(az + dAz, el + dEl, size);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    // The skyline, broken where it leaves the picture.
    final path = Path();
    Offset? prev;
    for (var i = 0; i <= skylineBins; i++) {
      final el = view.skyline[i % skylineBins];
      final p = el < -45 ? null : _at(i * 360 / skylineBins, el, size);
      if (p != null && prev != null && (p - prev).distance < size.width / 4) {
        path.lineTo(p.dx, p.dy);
      } else if (p != null) {
        path.moveTo(p.dx, p.dy);
      }
      prev = p;
    }
    canvas.drawPath(path, line);
    _ridges(canvas, size);

    // Labels, highest summits first, where they do not overlap; kept on the
    // screen, their line to the summit. Lines first, so none crosses a box.
    final placed = <({Offset at, Rect box, TextPainter label})>[];
    for (final s in view.summits) {
      if (placed.length >= maxLabels) break;
      final p = _at(s.azimuth, s.elevation, size);
      if (p == null || p.dx < 0 || p.dx > size.width || p.dy < 0 || p.dy > size.height) continue;
      final label = TextPainter(
        text: TextSpan(
          text: '${s.summit.name}\n',
          style: text.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
          children: [
            TextSpan(
              text: '${s.summit.ele} m · ${(s.distance / 1000).toStringAsFixed(s.distance < 10000 ? 1 : 0)} km',
              style: text.copyWith(color: Colors.white70),
            ),
          ],
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 160);
      final w = label.width + 8, h = label.height + 4;
      final x = (p.dx - w / 2).clamp(0.0, max(0.0, size.width - w)).toDouble();
      Rect? box;
      for (var lift = 24.0; lift < 24 + 3 * (h + 4); lift += h + 4) {
        final r = Rect.fromLTWH(x, p.dy - lift - h, w, h);
        if (r.top >= 0 && !placed.any((o) => o.box.overlaps(r))) {
          box = r;
          break;
        }
      }
      if (box != null) placed.add((at: p, box: box, label: label));
    }
    final dot = Paint()..color = Colors.white;
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.55);
    for (final l in placed) {
      canvas.drawLine(l.at, Offset(l.at.dx, l.box.bottom), line);
      canvas.drawCircle(l.at, 3, dot);
    }
    for (final l in placed) {
      canvas.drawRRect(RRect.fromRectAndRadius(l.box, const Radius.circular(4)), shade);
      l.label.paint(canvas, Offset(l.box.left + 4, l.box.top + 2));
    }
  }

  /// The nearer ridges: each edge joined to the one of the next ray at about
  /// its distance and angle; fainter the farther away. Only the rays in the
  /// picture.
  void _ridges(Canvas canvas, Size size) {
    final centre = pose.centre.azimuth - dAz;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke;
    final perBin = 360 / skylineBins;
    final half = (pose.fov * 0.75 / perBin).ceil();
    final first = (centre / perBin).round() - half;
    for (var k = first; k < first + 2 * half; k++) {
      final i = k % skylineBins, j = (k + 1) % skylineBins;
      final here = view.ridges[i], next = view.ridges[j];
      for (var a = 0; a < here.length; a += 2) {
        final d = here[a], el = here[a + 1];
        double? nearest, nearestEl;
        for (var b = 0; b < next.length; b += 2) {
          if ((next[b] - d).abs() < 150 + d * 0.1 &&
              (next[b + 1] - el).abs() < 1 &&
              (nearest == null || (next[b] - d).abs() < (nearest - d).abs())) {
            nearest = next[b];
            nearestEl = next[b + 1];
          }
        }
        if (nearest == null) continue;
        final p = _at(i * perBin, el, size), q = _at(j * perBin, nearestEl!, size);
        if (p == null || q == null || (p - q).distance > size.width / 4) continue;
        paint
          ..strokeWidth = d < 10000 ? 1.4 : 1
          ..color = Colors.white.withValues(alpha: (0.7 - d / maxDistance * 2).clamp(0.25, 0.7));
        canvas.drawLine(p, q, paint);
      }
    }
  }

  @override
  bool shouldRepaint(PeaksPainter old) => old.view != view || old.pose != pose || old.dAz != dAz || old.dEl != dEl;
}
