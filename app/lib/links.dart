import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/collections_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/journey_screen.dart';
import 'screens/route_screen.dart';

/// A route, journey or collection a link points to: the website's address
/// (https://…/routes/{id}?t=…) or the app's (alvyo://open/routes/{id}?t=…),
/// as the system hands it over, with or without scheme and host. A friend's
/// invite link (…/friends/invite/{token}) has the kind invite and the token
/// as its id.
typedef ItemLink = ({String kind, String id, String? token});

ItemLink? parseItemLink(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null) return null;
  // A custom scheme's first part is the host («open»), not a path segment.
  final parts = [if (uri.scheme == 'alvyo' && uri.host != 'open') uri.host, ...uri.pathSegments];
  for (var i = 0; i + 1 < parts.length; i++) {
    final kind = parts[i];
    final id = parts[i + 1];
    if (kind == 'friends' && id == 'invite' && i + 2 < parts.length) {
      final token = parts[i + 2];
      if (!RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(token)) return null;
      return (kind: 'invite', id: token, token: null);
    }
    if ({'routes', 'journeys', 'collections'}.contains(kind) &&
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$').hasMatch(id)) {
      final t = uri.queryParameters['t'];
      return (kind: kind, id: id, token: t == null || t.isEmpty ? null : t);
    }
  }
  return null;
}

/// Opens what a link points to on top of the app's screens.
void openLink(NavigatorState nav, Api api, ItemLink link) {
  if (link.token case final t?) api.shareTokens[link.id] = t;
  nav.push(
    MaterialPageRoute<void>(
      builder: (_) => switch (link.kind) {
        'journeys' => JourneyScreen(api: api, id: link.id, title: ''),
        'collections' => CollectionScreen(api: api, id: link.id, title: ''),
        'invite' => InviteScreen(api: api, token: link.id),
        _ => RouteScreen(api: api, id: link.id, title: ''),
      },
    ),
  );
}
