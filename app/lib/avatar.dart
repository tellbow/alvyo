import 'package:flutter/material.dart';

import 'api.dart';

/// A person's round profile picture, or a portrait icon without one.
class Avatar extends StatelessWidget {
  const Avatar(this.api, this.id, {super.key, this.radius = 20});

  final Api api;

  /// The picture's id; empty without one.
  final String id;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = Icon(Icons.person, size: radius * 1.2, color: scheme.primary);
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundImage: id.isEmpty ? null : NetworkImage(api.avatarUrl(id)),
      onForegroundImageError: id.isEmpty ? null : (_, _) {},
      child: icon,
    );
  }
}
