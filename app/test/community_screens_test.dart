import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/format.dart';
import 'package:alvyo/l10n/app_localizations.dart';
import 'package:alvyo/screens/collections_screen.dart';
import 'package:alvyo/screens/outline.dart';
import 'package:alvyo/screens/photos.dart';
import 'package:alvyo/screens/profile_tab.dart';
import 'package:alvyo/screens/social.dart';
import 'package:alvyo/screens/stage_sheet.dart';
import 'package:alvyo/screens/user_screen.dart';
import 'package:alvyo/settings.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

/// Answers by method and path; records the calls.
class _Server {
  _Server(this.answer);
  final http.Response Function(http.Request req) answer;
  final calls = <String>[];

  late final client = MockClient((req) async {
    final body = latin1.decode(req.bodyBytes);
    calls.add('${req.method} ${req.url.path}${body.isEmpty || body.startsWith('--') ? '' : ' $body'}');
    return answer(req);
  });
  late final api = Api('https://alvyo.test', token: 't', client: client);
}

Future<void> _pump(WidgetTester tester, Widget home, {Locale locale = const Locale('de')}) => tester.pumpWidget(
  MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: home),
  ),
);

/// Lets the fake server answer and the screen rebuild.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

Map<String, Object?> _me({bool notifyComments = false}) => {
  'id': 'u1',
  'username': 'wodan',
  'display_name': 'Wodan',
  'email': 'wodan@example.ch',
  'speed_factor': 1,
  'locale': 'de',
  'has_password': true,
  'notify_comments': notifyComments,
  'notify_follows': false,
  'email_verified': true,
};

void main() {
  testWidgets('the profile: light or dark, the language (also of e-mails) and notifications', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final server = _Server((req) {
      if (req.method == 'PATCH') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({..._me(notifyComments: body['notify_comments'] as bool? ?? false), ...body});
      }
      return _json(_me());
    });
    final settings = AppSettings();
    await _pump(tester, ProfileTab(api: server.api, onLogout: () {}, settings: settings));
    await _settle(tester);
    expect(find.text('@wodan · Mein Profil'), findsOneWidget);
    expect(find.textContaining('wodan@example.ch'), findsOneWidget);

    // Each setting shows its value and is chosen in a sheet.
    await tester.tap(find.byKey(const Key('theme')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dunkel'));
    await tester.pumpAndSettle();
    expect(settings.theme.value, ThemeMode.dark);

    await tester.tap(find.byKey(const Key('language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Français').last);
    await _settle(tester);
    expect(settings.locale.value, const Locale('fr'));
    expect(server.calls, contains('PATCH /api/v1/me {"locale":"fr"}'));

    await tester.tap(find.byKey(const Key('notifications')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notify-comments')));
    await _settle(tester);
    expect(server.calls, contains('PATCH /api/v1/me {"notify_comments":true}'));
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('notify-comments'))).value, isTrue);
  });

  testWidgets('the pace chosen in the profile: saved, and hiking times follow it', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => hikerPace.value = 1);
    final server = _Server((req) {
      if (req.method == 'PATCH') return _json({..._me(), ...jsonDecode(req.body) as Map<String, dynamic>});
      return _json(_me());
    });
    await _pump(tester, ProfileTab(api: server.api, onLogout: () {}, settings: AppSettings()));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('pace')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('150\u00a0%').last);
    await _settle(tester);
    expect(server.calls, contains('PATCH /api/v1/me {"speed_factor":1.5}'));
    expect(hikerPace.value, 1.5);
    expect(formatHikingTime(3600), '1\u00a0h 30\u00a0min');
  });

  testWidgets('deleting the account asks for the password and says when it is wrong', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var loggedOut = false;
    final server = _Server((req) {
      if (req.method == 'DELETE') {
        return (jsonDecode(req.body) as Map)['password'] == 'richtig'
            ? http.Response('', 204)
            : _json({'detail': 'wrong password'}, 403);
      }
      return _json(_me());
    });
    await _pump(tester, ProfileTab(api: server.api, onLogout: () => loggedOut = true, settings: AppSettings()));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('account-delete')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('account-delete-password')), 'falsch');
    await tester.tap(find.byKey(const Key('account-delete-confirm')));
    await _settle(tester);
    expect(find.text('Das Passwort ist falsch.'), findsOneWidget);
    expect(loggedOut, isFalse);
    await tester.enterText(find.byKey(const Key('account-delete-password')), 'richtig');
    await tester.tap(find.byKey(const Key('account-delete-confirm')));
    await _settle(tester);
    expect(loggedOut, isTrue);
  });

  testWidgets('liking, commenting and replying', (tester) async {
    var social = <String, Object?>{
      'likes': 0,
      'liked': false,
      'can_comment': true,
      'can_moderate': false,
      'comments_enabled': true,
      'comments': <Object>[
        {
          'id': 'c1',
          'author_username': 'anna',
          'author_name': 'Anna',
          'body': 'Schöne Tour',
          'created_at': '2026-09-27T10:00:00Z',
          'can_edit': false,
          'can_delete': false,
        },
      ],
    };
    final server = _Server((req) {
      if (req.url.path.endsWith('/like')) social = {...social, 'likes': 1, 'liked': true};
      if (req.method == 'POST') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        social = {
          ...social,
          'comments': [
            ...social['comments'] as List,
            {
              'id': 'c${(social['comments'] as List).length + 1}',
              'parent_id': body['parent_id'],
              'author_username': 'wodan',
              'author_name': 'Wodan',
              'body': body['body'],
              'created_at': '2026-09-27T12:00:00Z',
              'can_edit': true,
              'can_delete': true,
            },
          ],
        };
      }
      return _json(social);
    });
    await _pump(
      tester,
      SingleChildScrollView(
        child: SocialPanel(api: server.api, id: 'r1'),
      ),
    );
    await _settle(tester);
    expect(find.text('0 Mal gemerkt'), findsOneWidget);

    await tester.tap(find.byKey(const Key('like')));
    await _settle(tester);
    expect(find.text('1 Mal gemerkt'), findsOneWidget);

    await tester.tap(find.byKey(const Key('comment-write')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('comment-dialog-text')), 'Morgen gehe ich');
    await tester.tap(find.byKey(const Key('comment-dialog-ok')));
    await _settle(tester);
    expect(find.text('Morgen gehe ich'), findsOneWidget);

    await tester.tap(find.byKey(const Key('comment-menu-c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Antworten'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('comment-dialog-text')), 'Danke dir');
    await tester.tap(find.byKey(const Key('comment-dialog-ok')));
    await _settle(tester);
    expect(server.calls, contains('POST /api/v1/routes/r1/comments {"body":"Danke dir","parent_id":"c1"}'));
    // The reply is under its comment, indented.
    expect(tester.getTopLeft(find.text('Danke dir')).dx, greaterThan(tester.getTopLeft(find.text('Schöne Tour')).dx));
  });

  testWidgets('following someone: the profile\'s card, numbers and tabs', (tester) async {
    var followed = false;
    final server = _Server((req) {
      if (req.url.path.endsWith('/follow')) {
        followed = req.method == 'PUT';
        return _json({'followers': 1, 'following': 0, 'followed': followed, 'blocked': false});
      }
      return _json({
        'username': 'anna',
        'display_name': 'Anna',
        'since': '2026-09-01T00:00:00Z',
        'self': false,
        'followers': followed ? 1 : 0,
        'following': 3,
        'followed': followed,
        'blocked': false,
        'routes': [
          {
            'id': 'r1',
            'title': 'Gratweg',
            'owner_username': 'anna',
            'visibility': 'public',
            'version': 1,
            'totals': {
              'distance_m': 5000.0,
              'ascent_m': 300.0,
              'descent_m': 300.0,
              'duration_s': 7200,
              'sac_grade': 2,
              'sac_max': 2,
            },
          },
        ],
        'journeys': [
          {
            'id': 'j1',
            'title': 'Via Alpina',
            'stages': 3,
            'stages_done': 0,
            'distance_m': 40000.0,
            'ascent_m': 2000.0,
            'duration_s': 50000,
          },
        ],
        'outlines': {
          'r1': [
            [
              [8.0, 46.6],
              [8.01, 46.61],
            ],
          ],
        },
      });
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: UserScreen(api: server.api, username: 'anna'),
      ),
    );
    await _settle(tester);
    expect(find.text('@anna · dabei seit September 2026'), findsOneWidget);
    expect(find.text('A'), findsOneWidget); // the initial
    Finder stat(String label) => find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
      matching: find.byType(Text),
    );
    final counts = find.byKey(const Key('profile-counts'));
    expect(find.descendant(of: counts, matching: find.text('Follower')), findsOneWidget);
    expect(tester.widget<Text>(stat('Follower').first).data, '0');
    expect(tester.widget<Text>(stat('Folgt').first).data, '3');
    // Routes first, with the thumbnail; the journeys in the other tab.
    expect(find.text('Gratweg'), findsOneWidget);
    expect(find.byType(Outline), findsOneWidget);
    expect(find.text('Via Alpina'), findsNothing);
    await tester.tap(find.descendant(of: find.byKey(const Key('profile-tabs')), matching: find.text('Etappentouren')));
    await _settle(tester);
    expect(find.text('Via Alpina'), findsOneWidget);
    expect(find.text('Gratweg'), findsNothing);

    await tester.tap(find.byKey(const Key('follow')));
    await _settle(tester);
    expect(server.calls, contains('PUT /api/v1/users/anna/follow'));
    expect(tester.widget<Text>(stat('Follower').first).data, '1');
    expect(find.byKey(const Key('unfollow')), findsOneWidget);
  });

  group('a stage', () {
    Map<String, Object?> place(String id, String name, String ref) => {
      'id': id,
      'kind': 'pt_stop',
      'name': name,
      'detail': '',
      'at': [9.4, 47.0],
      'distance_m': 0,
      'ref': ref,
    };
    Map<String, Object?> stage(String id, {Object? start, Object? end, String? transfer, String accommodation = ''}) =>
        {
          'id': id,
          'version': 2,
          'title': '',
          'planned_date': '2026-07-04',
          'status': 'planned',
          'transfer_before': transfer,
          'start_place': start,
          'end_place': end,
          'accommodation': accommodation,
          'accommodation_booked': false,
          'notes': '',
          'route': {'id': 'r-$id'},
        };
    Map<String, Object?> journey({String accommodation = ''}) => {
      'id': 'j1',
      'title': 'Via Alpina',
      'can_edit': true,
      'role': 'owner',
      'stage_list': [
        stage('s1', end: place('p1', 'Sargans', '8509411')),
        stage(
          's2',
          start: place('p2', 'Weisstannen, Oberdorf', '8509074'),
          end: place('p3', 'Elm, Station', '8503601'),
          transfer: 'pt',
          accommodation: accommodation,
        ),
      ],
      'totals': {'distance_m': 1.0, 'ascent_m': 0.0, 'descent_m': 0.0, 'duration_s': 60, 'sac_grade': 1, 'sac_max': 1},
      'progress': {'stages_done': 0, 'stages_total': 2},
    };

    testWidgets('its accommodation is changed, with its version', (tester) async {
      String? ifMatch;
      final server = _Server((req) {
        ifMatch = req.headers['if-match'];
        return _json(journey(accommodation: 'Gasthaus Gemse'));
      });
      JourneyDetail? changed;
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => changed = await showStage(context, server.api, JourneyDetail.fromJson(journey()), 1),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stage-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('stage-accommodation')), 'Gasthaus Gemse');
      await tester.ensureVisible(find.byKey(const Key('stage-save')));
      await tester.tap(find.byKey(const Key('stage-save')));
      await _settle(tester);
      expect(server.calls, ['PATCH /api/v1/journeys/j1/stages/s2 {"accommodation":"Gasthaus Gemse"}']);
      expect(ifMatch, '"2"');
      expect(changed?.stages[1].accommodation, 'Gasthaus Gemse');
    });

    testWidgets('public transport: the transfer from the stage before, and the SBB timetable', (tester) async {
      final server = _Server((req) => _json({'trips': <Object>[]}));
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showStage(context, server.api, JourneyDetail.fromJson(journey()), 1),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sbb-transfer')), findsOneWidget);
      expect(find.byKey(const Key('sbb-start')), findsOneWidget);
      expect(find.byKey(const Key('sbb-end')), findsOneWidget);
      expect(find.byKey(const Key('stage-from-here')), findsOneWidget);
      await tester.tap(find.byKey(const Key('stage-transfer-connections')));
      await _settle(tester);
      expect(find.text('Sargans → Weisstannen, Oberdorf'), findsOneWidget);
      expect(find.byKey(const Key('connections-none')), findsOneWidget);
      expect(server.calls.single, startsWith('GET /api/v1/connections'));
    });
  });

  testWidgets('adding to a collection, and once more', (tester) async {
    var added = false;
    final server = _Server((req) {
      if (req.method == 'POST') {
        if (added) return _json({'detail': 'already in the collection'}, 409);
        added = true;
        return _json({
          'id': 'c1',
          'title': 'Herbst',
          'owner_username': 'wodan',
          'role': 'owner',
          'can_edit': true,
          'item_list': <Object>[],
        });
      }
      return _json({
        'collections': [
          {'id': 'c1', 'title': 'Herbst', 'owner_username': 'wodan', 'items': 3, 'visibility': 'private'},
        ],
      });
    });
    await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => addToCollection(context, server.api, 'r1', journey: false),
          child: const Text('add'),
        ),
      ),
    );
    for (final message in ['Hinzugefügt zu «Herbst»', 'Schon in «Herbst»']) {
      await tester.tap(find.text('add'));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('pick-c1')));
      await _settle(tester);
      expect(find.text(message), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.text('add'))).clearSnackBars();
      await tester.pumpAndSettle();
    }
    expect(server.calls.where((c) => c.startsWith('POST')), [
      'POST /api/v1/collections/c1/items {"route_id":"r1"}',
      'POST /api/v1/collections/c1/items {"route_id":"r1"}',
    ]);
  });

  testWidgets('a collection shared: its link, and someone invited by e-mail', (tester) async {
    var grants = <Object>[];
    final server = _Server((req) {
      switch ((req.method, req.url.path)) {
        case ('GET', '/api/v1/collections/c1'):
          return _json({
            'id': 'c1',
            'title': 'Herbst',
            'owner_username': 'wodan',
            'role': 'owner',
            'can_edit': true,
            'visibility': 'unlisted',
            'share_token': 'tok',
            'item_list': <Object>[],
          });
        case ('POST', '/api/v1/collections/c1/grants'):
          grants = [
            {'id': 'g1', 'role': 'viewer', 'email': 'anna@example.ch'},
          ];
          return _json({'grants': grants});
        case ('GET', '/api/v1/collections/c1/grants'):
          return _json({'grants': grants});
      }
      return _json({'detail': 'not found'}, 404);
    });
    await _pump(tester, CollectionScreen(api: server.api, id: 'c1', title: 'Herbst'));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('item-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-share')));
    await _settle(tester);
    expect(find.text('https://alvyo.test/collections/c1?t=tok'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('share-who')), 'anna@example.ch');
    await tester.tap(find.byKey(const Key('share-invite')));
    await _settle(tester);
    expect(server.calls, contains('POST /api/v1/collections/c1/grants {"email":"anna@example.ch","role":"viewer"}'));
    expect(find.textContaining('anna@example.ch'), findsOneWidget);
  });

  testWidgets('photos: added from the library, one after the other', (tester) async {
    var photos = <Object>[];
    final server = _Server((req) {
      if (req.method == 'POST') {
        photos = [
          ...photos,
          {'id': 'p${photos.length}', 'caption': '', 'width': 10, 'height': 10, 'uploader': 'wodan'},
        ];
      }
      return _json({'can_edit': true, 'photos': photos});
    });
    await _pump(
      tester,
      PhotoStrip(
        api: server.api,
        id: 'r1',
        pick: (source) async => [
          for (final name in ['a.jpg', 'b.jpg']) XFile.fromData(Uint8List.fromList([0xff, 0xd8, 0xff]), name: name),
        ],
      ),
    );
    await _settle(tester);
    expect(find.byKey(const Key('photo-0')), findsNothing);
    await tester.tap(find.byKey(const Key('photo-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photo-library')));
    await _settle(tester);
    expect(server.calls.where((c) => c == 'POST /api/v1/routes/r1/photos').length, 2);
    expect(find.byKey(const Key('photo-1')), findsOneWidget);
  });

  test('settings without a Keychain (tests) follow the phone', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => throw PlatformException(code: 'no keychain'),
    );
    final s = AppSettings();
    await s.loaded;
    expect(s.theme.value, ThemeMode.system);
    expect(s.locale.value, isNull);
    await s.setTheme(ThemeMode.light);
    expect(s.theme.value, ThemeMode.light, reason: 'switched, if not remembered');
  });
}
