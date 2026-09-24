import 'dart:convert';
import 'dart:io';

import '../api.dart';
import '../format.dart';
import 'tracker.dart';

/// Uploads finished hikes (see Recording.finish) and deletes each once the
/// server has it. Hikes the server can never take (outside Switzerland, too
/// short) are deleted too; the others wait for the next try, unreadable ones
/// are set aside (.bad). Returns how many were uploaded.
Future<int> uploadHikes(Api api, Directory recordings) async {
  final done = Directory('${recordings.path}/done');
  if (!await done.exists()) return 0;
  var uploaded = 0;
  for (final file in (await done.list().toList()).whereType<File>()) {
    if (!file.path.endsWith('.json')) continue;
    final Map<String, dynamic> j;
    final DateTime started;
    final List<({double lon, double lat, DateTime time})> points;
    try {
      j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      started = DateTime.parse(j['started'] as String);
      points = uploadPoints([for (final f in j['fixes'] as List) Fix.fromJson(f as Map<String, dynamic>)]);
    } on Object {
      await file.rename('${file.path}.bad'); // unreadable: set aside, not in the way of the others
      continue;
    }
    try {
      if (points.length >= 2) {
        await api.uploadHike(
          id: j['started'] as String,
          routeId: j['route_id'] as String?,
          title: hikeTitle(j['title'] as String, started),
          points: points,
        );
        uploaded++;
      }
      await file.delete();
    } on ApiException catch (e) {
      // Only what the server can never take; anything else is tried again.
      if (e.status == 422 && e.message.startsWith('the hike ')) await file.delete();
      if (e.status == 401) rethrow; // logged out: no use trying the others
    } on Exception {
      return uploaded; // offline: later
    }
  }
  return uploaded;
}

/// A hike's title: the route's and the date, within the server's 120
/// characters.
String hikeTitle(String route, DateTime started) {
  final date = ', ${formatDate(started)}';
  final chars = route.runes.toList();
  final keep = 120 - date.length;
  return (chars.length > keep ? String.fromCharCodes(chars.take(keep)).trimRight() : route) + date;
}

/// The positions worth uploading: those accurate to 30 m, at least 5 m apart
/// (the Watch records every second; the server simplifies to 5 m anyway),
/// and the last one, which ends the hike's time.
List<({double lon, double lat, DateTime time})> uploadPoints(List<Fix> fixes) {
  final accurate = [
    for (final f in fixes)
      if (f.accuracyM <= 30) f,
  ];
  final out = <({double lon, double lat, DateTime time})>[];
  Fix? kept;
  for (final (i, f) in accurate.indexed) {
    if (kept == null || i == accurate.length - 1 || trackLengthM([kept, f]) >= 5) {
      out.add((lon: f.lon, lat: f.lat, time: f.time));
      kept = f;
    }
  }
  return out;
}
