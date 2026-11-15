import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // A key twice in a file: the last wins silently and the first text is lost.
  test('no text key twice in an .arb file', () {
    for (final f in Directory('lib/l10n').listSync().whereType<File>().where((f) => f.path.endsWith('.arb'))) {
      final keys = RegExp(r'^  "([^"]+)":', multiLine: true).allMatches(f.readAsStringSync()).map((m) => m[1]!);
      final seen = <String>{};
      expect(keys.where((k) => !seen.add(k)), isEmpty, reason: f.path);
    }
  });
}
