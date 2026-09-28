import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alvyo/api.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

const _social = {
  'likes': 2,
  'liked': true,
  'can_comment': true,
  'can_moderate': false,
  'comments_enabled': true,
  'comments': [
    {
      'id': 'c1',
      'author_username': 'anna',
      'author_name': 'Anna',
      'body': 'Schön!',
      'created_at': '2026-09-27T10:00:00Z',
      'can_edit': false,
      'can_delete': false,
    },
    {
      'id': 'c2',
      'parent_id': 'c1',
      'author_username': 'wodan',
      'author_name': 'Wodan',
      'body': 'Danke',
      'created_at': '2026-09-27T11:00:00Z',
      'edited_at': '2026-09-27T11:05:00Z',
      'can_edit': true,
      'can_delete': true,
    },
  ],
};

void main() {
  test('changes carry the version as If-Match; a conflict is 412', () async {
    final seen = <String, String?>{};
    final client = MockClient((req) async {
      seen['${req.method} ${req.url.path}'] = req.headers['if-match'];
      if (req.url.path == '/api/v1/journeys/j1') return _json({'title': 'x'}, 412);
      expect(jsonDecode(req.body), {'title': 'Neu', 'visibility': 'public'});
      return _json({
        'id': 'r1',
        'title': 'Neu',
        'owner_username': 'wodan',
        'visibility': 'public',
        'version': 4,
        'totals': {
          'distance_m': 1.0,
          'ascent_m': 0.0,
          'descent_m': 0.0,
          'duration_s': 60,
          'sac_grade': 1,
          'sac_max': 1,
        },
        'legs': <Object>[],
      });
    });
    final api = Api('https://alvyo.test', token: 't', client: client);
    final r = await api.updateRoute('r1', 3, {'title': 'Neu', 'visibility': 'public'});
    expect(r.visibility, 'public');
    expect(r.version, 4);
    expect(seen['PATCH /api/v1/routes/r1'], '"3"');
    await expectLater(
      api.updateJourney('j1', 7, {'title': 'x'}),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 412)),
    );
    expect(seen['PATCH /api/v1/journeys/j1'], '"7"');
  });

  test('likes and comments of routes and journeys', () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}${req.body.isEmpty ? '' : ' ${req.body}'}');
      return _json(_social);
    });
    final api = Api('https://alvyo.test', token: 't', client: client);
    final s = await api.social('r1');
    expect(s.likes, 2);
    expect(s.comments.last.parentId, 'c1');
    expect(s.comments.last.edited, isTrue);
    await api.like('j1', false, journey: true);
    await api.comment('r1', 'Hallo', parentId: 'c1');
    await api.editComment('r1', 'c2', 'Danke!');
    await api.setComments('j1', false, journey: true);
    expect(calls, [
      'GET /api/v1/routes/r1/social',
      'DELETE /api/v1/journeys/j1/like',
      'POST /api/v1/routes/r1/comments {"body":"Hallo","parent_id":"c1"}',
      'PATCH /api/v1/routes/r1/comments/c2 {"body":"Danke!"}',
      'PATCH /api/v1/journeys/j1/social {"comments_enabled":false}',
    ]);
  });

  test('a photo goes up as a multipart form; photos are loaded with the token', () async {
    final client = MockClient((req) async {
      expect(req.method, 'POST');
      expect(req.url.path, '/api/v1/journeys/j1/photos');
      expect(req.headers['content-type'], startsWith('multipart/form-data'));
      expect(req.headers['authorization'], 'Bearer t');
      final body = latin1.decode(req.bodyBytes);
      expect(body, contains('name="file"; filename="IMG_1.HEIC"'));
      expect(body, contains('JPEGDATA'));
      return _json({
        'can_edit': true,
        'photos': [
          {'id': 'p1', 'caption': '', 'width': 4032, 'height': 3024, 'uploader': 'wodan'},
        ],
      });
    });
    final api = Api('https://alvyo.test', token: 't', client: client);
    final p = await api.addPhoto('j1', utf8.encode('JPEGDATA'), 'IMG_1.HEIC', journey: true);
    expect(p.photos.single.width, 4032);
    expect(api.photoUrl('p1', 'thumb'), 'https://alvyo.test/api/v1/photos/p1/thumb');
    expect(api.authHeaders, {'Authorization': 'Bearer t'});
  });

  test('invitations go to a username or an e-mail address', () async {
    final bodies = <Object?>[];
    final client = MockClient((req) async {
      bodies.add(jsonDecode(req.body));
      return _json({
        'grants': [
          {'id': 'g1', 'role': 'editor', 'created_at': '2026-09-27T10:00:00Z', 'email': 'eva@example.ch'},
        ],
      });
    });
    final api = Api('https://alvyo.test', token: 't', client: client);
    await api.invite('r1', 'anna', 'viewer');
    final grants = await api.invite('r1', 'eva@example.ch', 'editor');
    expect(bodies, [
      {'username': 'anna', 'role': 'viewer'},
      {'email': 'eva@example.ch', 'role': 'editor'},
    ]);
    expect(grants.single.username, '', reason: 'invited, no account yet');
  });

  test('the feed pages on with before', () async {
    final asked = <String?>[];
    final client = MockClient((req) async {
      asked.add(req.url.queryParameters['before']);
      return _json({
        'items': [
          {
            'kind': 'journey',
            'id': 'j1',
            'title': 'Via Alpina',
            'owner_username': 'anna',
            'owner_name': 'Anna',
            'published_at': '2026-09-20T08:00:00Z',
            'distance_m': 1000.0,
            'ascent_m': 10.0,
            'duration_s': 600,
            'sac_grade': 2,
            'sac_max': 3,
            'stages': 4,
          },
        ],
        if (asked.length == 1) 'next': '2026-09-20T08:00:00Z',
      });
    });
    final api = Api('https://alvyo.test', token: 't', client: client);
    final first = await api.feed();
    expect(first.items.single.stages, 4);
    final second = await api.feed(before: first.next);
    expect(second.next, isNull);
    expect(asked, [null, '2026-09-20T08:00:00.000Z']);
  });

  test('connections between two stops', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/api/v1/connections');
      expect(req.url.queryParameters, {
        'from': '8509074',
        'to': '8509411',
        'date': '2026-07-04',
        'time': '07:30',
        'arrive': 'false',
      });
      return _json({
        'trips': [
          {
            'start': '2026-07-04T05:35:00Z',
            'end': '2026-07-04T06:20:00Z',
            'transfers': 1,
            'legs': [
              {
                'kind': 'ride',
                'from': 'Sargans',
                'to': 'Mels',
                'line': 'B 441',
                'departure': '2026-07-04T05:35:00Z',
                'arrival': '2026-07-04T05:45:00Z',
                'platform': 'B',
                'delay_min': 2,
              },
              {'kind': 'walk', 'from': 'Mels', 'to': 'Mels, Post', 'duration_min': 3},
            ],
          },
        ],
      });
    });
    final api = Api('https://alvyo.test', token: 't', client: client);
    final trips = await api.connections('8509074', '8509411', DateTime(2026, 7, 4), time: '07:30');
    expect(trips.single.legs.first.delayMin, 2);
    expect(trips.single.legs.last.ride, isFalse);
    expect(trips.single.legs.last.walkMin, 3);
  });

  test('settings, and deleting the account with the password', () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path} ${req.body}');
      if (req.method == 'DELETE') return http.Response('', 204);
      return _json({
        'id': 'u1',
        'username': 'wodan',
        'display_name': 'Wodan',
        'speed_factor': 1,
        'locale': 'fr',
        'notify_comments': true,
        'notify_follows': false,
        'has_password': true,
        'email_verified': false,
      });
    });
    final api = Api('https://alvyo.test', token: 't', client: client);
    final me = await api.updateMe(locale: 'fr');
    expect(me.locale, 'fr');
    expect(me.notifyComments, isTrue);
    expect(me.emailVerified, isFalse);
    await api.deleteMe(password: 'geheim');
    expect(calls, ['PATCH /api/v1/me {"locale":"fr"}', 'DELETE /api/v1/me {"password":"geheim"}']);
  });
}
