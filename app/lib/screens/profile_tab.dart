import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/app_localizations.dart';

/// The account: who is logged in, on which server, and logging out.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key, required this.api, required this.onLogout});
  final Api api;
  final VoidCallback onLogout;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  late final Future<Me> _me = widget.api.me();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: FutureBuilder(
              future: _me,
              builder: (context, snap) {
                final me = snap.data;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    if (me != null) Text(me.displayName, style: theme.textTheme.headlineSmall),
                    if (me != null) Text('@${me.username}'),
                    Text(
                      '${t.server}: ${Uri.parse(widget.api.server).host}',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const Key('logout'),
          onPressed: widget.onLogout,
          icon: const Icon(Icons.logout),
          label: Text(t.logout),
        ),
      ],
    );
  }
}
