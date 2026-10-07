import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../api.dart';
import 'pack.dart';

/// The pack for recognising mountains, kept in the app's files: downloaded
/// once, then used without reception.
class PeakStore {
  PeakStore(this.file);

  static Future<PeakStore> open() async =>
      PeakStore(File('${(await getApplicationSupportDirectory()).path}/peaks/peaks-v1.bin.gz'));

  final File file;

  bool get saved => file.existsSync();

  /// Reads the pack in the background (about 16 MB of heights).
  Future<PeakPack> load() => _decode(file.path);

  /// Downloads the pack, reporting the bytes so far and the whole (0 while
  /// unknown); while the server still builds it, it is asked again.
  Future<void> download(
    Api api, {
    void Function(int got, int total)? progress,
    Duration wait = const Duration(seconds: 10),
  }) async {
    for (var attempt = 0; ; attempt++) {
      final r = await api.peaksPack();
      if (r.statusCode == 503 && attempt < 30) {
        await r.stream.drain<void>();
        await Future<void>.delayed(wait);
        continue;
      }
      if (r.statusCode != 200) {
        await r.stream.drain<void>();
        throw HttpException('peaks pack: ${r.statusCode}');
      }
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.part');
      final sink = tmp.openWrite();
      var got = 0;
      try {
        await for (final chunk in r.stream) {
          sink.add(chunk);
          got += chunk.length;
          progress?.call(got, r.contentLength ?? 0);
        }
      } finally {
        await sink.close();
      }
      await tmp.rename(file.path);
      await _excludeFromBackup();
      return;
    }
  }

  /// It can be downloaded again: out of iCloud backups (AppDelegate.swift).
  Future<void> _excludeFromBackup() async {
    if (!Platform.isIOS) return;
    try {
      await const MethodChannel('alvyo/backup').invokeMethod<bool>('exclude', file.parent.path);
    } on PlatformException {
      // backed up after all
    }
  }
}

/// Top-level, so the isolate gets only the path.
Future<PeakPack> _decode(String path) => Isolate.run(() => PeakPack.decode(File(path).readAsBytesSync()));
