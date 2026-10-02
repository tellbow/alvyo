import 'dart:ui';

import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/app_localizations.dart';
import '../settings.dart';
import 'account_screens.dart';
import 'collections_screen.dart';
import 'discover_screen.dart';
import 'user_screen.dart';

/// The account: who is logged in, the profile, collections and map of
/// one's tours, the settings, logging out and deleting the account.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key, required this.api, required this.onLogout, required this.settings});
  final Api api;
  final VoidCallback onLogout;
  final AppSettings settings;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  late Future<Me> _me = widget.api.me();

  static const _languages = {'de': 'Deutsch', 'en': 'English', 'fr': 'Français', 'it': 'Italiano'};

  /// Paces to choose from, as on the website: hiking times as a multiple of
  /// the signposts'.
  static const _paces = [0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.75, 2.0];

  /// The app's language, and on the server the language of e-mails: the
  /// phone's (among those there are) when automatic.
  Future<void> _language(String? code) async {
    await widget.settings.setLocale(code == null ? null : Locale(code));
    final lang =
        code ??
        basicLocaleListResolution(PlatformDispatcher.instance.locales, AppLocalizations.supportedLocales).languageCode;
    _update(() => widget.api.updateMe(locale: lang));
  }

  /// A change of the account; shows it as the server has it.
  void _update(Future<Me> Function() call) {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final next = call();
    next.then(
      (me) {
        if (mounted) {
          setState(() {
            _me = Future.value(me);
          });
        }
      },
      onError: (Object _) {
        messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
      },
    );
  }

  void _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return FutureBuilder(
      future: _me,
      builder: (context, snap) {
        final me = snap.data;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    if (me != null) Text(me.displayName, style: theme.textTheme.headlineSmall),
                    if (me != null) Text('@${me.username}${me.email.isEmpty ? '' : ' · ${me.email}'}'),
                    Text('${t.server}: ${Uri.parse(widget.api.server).host}', style: muted),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (me != null)
              ListTile(
                key: const Key('profile-mine'),
                leading: const Icon(Icons.person_outline),
                title: Text(t.profileMine),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _push(UserScreen(api: widget.api, username: me.username)),
              ),
            ListTile(
              key: const Key('collections'),
              leading: const Icon(Icons.collections_bookmark_outlined),
              title: Text(t.collectionsTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(CollectionsScreen(api: widget.api)),
            ),
            ListTile(
              key: const Key('my-map'),
              leading: const Icon(Icons.map_outlined),
              title: Text(t.myMapTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(DiscoverScreen(api: widget.api, mine: true)),
            ),
            const Divider(height: 24),
            Text(t.settingsTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(t.themeTitle, style: muted),
            const SizedBox(height: 6),
            ValueListenableBuilder(
              valueListenable: widget.settings.theme,
              builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                key: const Key('theme'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: ThemeMode.system, label: Text(t.themeSystem)),
                  ButtonSegment(value: ThemeMode.light, label: Text(t.themeLight)),
                  ButtonSegment(value: ThemeMode.dark, label: Text(t.themeDark)),
                ],
                selected: {mode},
                onSelectionChanged: (s) => widget.settings.setTheme(s.first),
              ),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder(
              valueListenable: widget.settings.locale,
              builder: (context, locale, _) => DropdownMenu<String?>(
                key: const Key('language'),
                label: Text(t.languageTitle),
                expandedInsets: EdgeInsets.zero,
                initialSelection: locale?.languageCode,
                onSelected: _language,
                dropdownMenuEntries: [
                  DropdownMenuEntry(value: null, label: t.themeSystem),
                  for (final e in _languages.entries) DropdownMenuEntry(value: e.key, label: e.value),
                ],
              ),
            ),
            if (me != null) ...[
              const SizedBox(height: 16),
              DropdownMenu<double>(
                key: const Key('pace'),
                label: Text(t.accountPace),
                helperText: t.accountPaceHint,
                expandedInsets: EdgeInsets.zero,
                initialSelection: me.speedFactor,
                onSelected: (v) => v == null ? null : _update(() => widget.api.updateMe(speedFactor: v)),
                dropdownMenuEntries: [
                  for (final p in {..._paces, me.speedFactor}.toList()..sort())
                    DropdownMenuEntry(value: p, label: p == 1 ? t.accountPaceSignposts : '${(p * 100).round()}\u00a0%'),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text(t.accountNotifications, style: muted),
            SwitchListTile(
              key: const Key('notify-comments'),
              contentPadding: EdgeInsets.zero,
              title: Text(t.accountNotifyComments),
              value: me?.notifyComments ?? false,
              onChanged: me == null ? null : (v) => _update(() => widget.api.updateMe(notifyComments: v)),
            ),
            SwitchListTile(
              key: const Key('notify-follows'),
              contentPadding: EdgeInsets.zero,
              title: Text(t.accountNotifyFollows),
              value: me?.notifyFollows ?? false,
              onChanged: me == null ? null : (v) => _update(() => widget.api.updateMe(notifyFollows: v)),
            ),
            ListTile(
              key: const Key('homes'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.home_outlined),
              title: Text(t.homesTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(HomesScreen(api: widget.api)),
            ),
            ListTile(
              key: const Key('contacts'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.contact_mail_outlined),
              title: Text(t.contactsTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(ContactsScreen(api: widget.api)),
            ),
            ListTile(
              key: const Key('blocked'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.block),
              title: Text(t.blockedTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(BlockedScreen(api: widget.api)),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('logout'),
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout),
              label: Text(t.logout),
            ),
            const SizedBox(height: 8),
            if (me != null)
              TextButton(
                key: const Key('account-delete'),
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                onPressed: () => deleteAccount(context, widget.api, me, onDeleted: widget.onLogout),
                child: Text(t.accountDeleteTitle),
              ),
          ],
        );
      },
    );
  }
}
