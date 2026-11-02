import 'dart:convert';

import 'package:alvyo/api.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('finds a nonce with the zero bits asked for', () async {
    final nonce = await solveChallenge('salt.1.12.sig', 12);
    final hash = sha256.convert(utf8.encode('salt.1.12.sig:$nonce')).bytes;
    expect(hash[0], 0);
    expect(hash[1] & 0xf0, 0);
  });

  test('a form sends the answer, and a new one each time', () async {
    final sent = <Map<String, dynamic>>[];
    var issued = 0;
    final api = Api(
      'https://alvyo.test',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/challenge')) {
          return http.Response(jsonEncode({'challenge': 'c${++issued}', 'bits': 4, 'wait_ms': 1}), 200);
        }
        sent.add(jsonDecode(r.body) as Map<String, dynamic>);
        return http.Response('', 204);
      }),
    );
    await api.report(kind: 'user', username: 'bot', reason: 'spam');
    await api.report(kind: 'user', username: 'bot', reason: 'spam');
    expect([for (final b in sent) b['challenge']], ['c1', 'c2']);
    final hash = sha256.convert(utf8.encode('c1:${sent[0]['nonce']}')).bytes;
    expect(hash[0] & 0xf0, 0);
  });

  test('without a challenge the form is sent anyway, and the next one asks again', () async {
    var asked = 0;
    final sent = <Map<String, dynamic>>[];
    final api = Api(
      'https://alvyo.test',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/challenge')) {
          asked++;
          return http.Response('{"detail":"down"}', 503);
        }
        sent.add(jsonDecode(r.body) as Map<String, dynamic>);
        return http.Response('', 204);
      }),
    );
    api.prepareProof();
    await api.report(kind: 'user', username: 'bot', reason: 'spam');
    await api.report(kind: 'user', username: 'bot', reason: 'spam');
    expect(sent[0].containsKey('challenge'), isFalse);
    expect(asked, greaterThanOrEqualTo(2));
  });
}
