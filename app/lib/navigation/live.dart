import 'dart:convert';
import 'dart:io';

import '../api.dart';
import 'tracker.dart';

/// Sends a shared hike's positions: one a minute collected, sent every
/// [every]; what cannot be sent (no connection) goes with the next try.
class LiveSender {
  LiveSender(
    this.api,
    this.shareId, {
    this.every = const Duration(minutes: 5),
    this.retry = const Duration(minutes: 1),
    this.timeout = const Duration(seconds: 30),
  });

  final Api api;
  final String shareId;
  final Duration every, retry;

  /// A request that hangs (weak reception) counts as failed, so that the
  /// next try is not held up for the rest of the hike.
  final Duration timeout;

  final _pending = <Fix>[];
  DateTime? _sent, _tried;

  /// When the minute of the last waiting position began.
  DateTime? _slot;
  Future<void>? _sending;

  /// At most this many positions wait (a day offline); the oldest go first.
  static const maxPending = 1500;

  /// Positions waiting to be sent.
  int get pending => _pending.length;

  /// Takes a position; sends when due.
  Future<void> add(Fix f) {
    if (f.accuracyM > 75) return Future.value();
    if (_pending.isNotEmpty && _slot != null && f.time.difference(_slot!) < const Duration(minutes: 1)) {
      _pending[_pending.length - 1] = f; // the latest of the minute counts
    } else {
      _pending.add(f);
      _slot = f.time;
      if (_pending.length > maxPending) _pending.removeAt(0);
    }
    final now = f.time;
    final due = _sent == null || now.difference(_sent!) >= every;
    final retried = _tried == null || now.difference(_tried!) >= retry;
    if (!due || !retried || _sending != null) return Future.value();
    return _sending = _send(now).whenComplete(() => _sending = null);
  }

  Future<void> _send(DateTime now) async {
    _tried = now;
    final batch = List.of(_pending);
    // Those sent, not those that took their place meanwhile (the latest of
    // the minute, or the oldest dropped).
    void sent() {
      final gone = Set<Fix>.identity()..addAll(batch);
      _pending.removeWhere(gone.contains);
    }

    try {
      await api
          .livePositions(shareId, [for (final f in batch) (lon: f.lon, lat: f.lat, time: f.time)])
          .timeout(timeout);
      sent();
      _sent = now;
    } on ApiException catch (e) {
      if (e.status == 404 || e.status == 409) _pending.clear(); // ended elsewhere: nothing to send
      if (e.status == 422) sent(); // never taken (e.g. a position far off): not in the way of the next
    } on Exception {
      // offline: next time
    }
  }
}

/// Ends of shares that could not be sent yet, kept in a file so that the
/// contacts are not alerted about a hike that did end.
class LiveOutbox {
  LiveOutbox(this.root, {this.timeout = const Duration(seconds: 10)});
  final Directory root;

  /// A request that hangs counts as no connection: finishing the hike must
  /// not wait for it.
  final Duration timeout;

  File get _file => File('${root.path}/live_end.json');

  Future<List<String>> _ids() async {
    try {
      return [for (final id in jsonDecode(await _file.readAsString()) as List) id as String];
    } on Object {
      return [];
    }
  }

  Future<void> _write(List<String> ids) async {
    await root.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(ids));
    await tmp.rename(_file.path);
  }

  /// Ends the share now, or later if there is no connection.
  Future<void> end(Api api, String id) async {
    try {
      await api.endLive(id).timeout(timeout);
    } on ApiException {
      // gone or ended already: nothing to do
    } on Exception {
      await _write({...await _ids(), id}.toList());
    }
  }

  /// Sends the ends that wait; returns how many are left.
  Future<int> flush(Api api) async {
    final left = <String>[];
    for (final id in await _ids()) {
      try {
        await api.endLive(id).timeout(timeout);
      } on ApiException {
        // done or gone
      } on Exception {
        left.add(id);
      }
    }
    await _write(left);
    return left.length;
  }
}
