import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/links.dart';

const _id = '0199a000-0000-7000-8000-000000000001';

void main() {
  test('links to routes, journeys and collections, from the website or the app', () {
    expect(parseItemLink('https://alvyo.tellbow.ch/routes/$_id'), (kind: 'routes', id: _id, token: null));
    expect(parseItemLink('https://alvyo.tellbow.ch/fr/journeys/$_id?t=abc'), (kind: 'journeys', id: _id, token: 'abc'));
    expect(parseItemLink('alvyo://open/collections/$_id?t=x'), (kind: 'collections', id: _id, token: 'x'));
    expect(parseItemLink('alvyo://routes/$_id'), (kind: 'routes', id: _id, token: null));
    expect(parseItemLink('/routes/$_id?t='), (kind: 'routes', id: _id, token: null)); // as Flutter hands it over
    expect(parseItemLink('/'), isNull);
    expect(parseItemLink('https://alvyo.tellbow.ch/routes/map'), isNull);
    expect(parseItemLink('https://alvyo.tellbow.ch/u/wodan'), isNull);
    // A friend's invite link: the token as id.
    expect(parseItemLink('https://alvyo.tellbow.ch/friends/invite/AbCdEfGhIjKlMnOpQrStUv'), (
      kind: 'invite',
      id: 'AbCdEfGhIjKlMnOpQrStUv',
      token: null,
    ));
    expect(parseItemLink('alvyo://open/friends/invite/AbCdEfGhIjKlMnOpQrStUv'), (
      kind: 'invite',
      id: 'AbCdEfGhIjKlMnOpQrStUv',
      token: null,
    ));
    expect(parseItemLink('https://alvyo.tellbow.ch/friends/invite/x'), isNull);
  });

  test('an item opened from a link keeps its share token on every call', () async {
    final asked = <Uri>[];
    final api = Api(
      'https://alvyo.test',
      client: MockClient((req) async {
        asked.add(req.url);
        return http.Response('{"pois": []}', 200, headers: {'content-type': 'application/json'});
      }),
    );
    api.shareTokens[_id] = 'secret';
    await api.pois(_id);
    await api.pois('0199a000-0000-7000-8000-000000000002');
    expect(asked[0].queryParameters['t'], 'secret');
    expect(asked[1].queryParameters.containsKey('t'), isFalse);
  });
}
