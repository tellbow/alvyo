import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../analytics.dart';
import '../api.dart';
import '../l10n/app_localizations.dart';
import '../settings.dart';
import 'about_screen.dart';
import 'account_screens.dart';
import 'devices_screen.dart';
import 'import_tile.dart';
import 'friends_screen.dart';
import 'statistics_sheet.dart';
import 'tab_header.dart';
import 'user_screen.dart';
import 'wide.dart';

/// Profil (requirement 69): who one is, friends and connected devices, the
/// settings, the account (homes, contacts, blocked), logging out and
/// deleting it.
class ProfileTab extends StatefulWidget {
  const ProfileTab({
    super.key,
    required this.api,
    required this.onLogout,
    required this.settings,
    this.analytics,
    this.onImported,
  });
  final Api api;
  final VoidCallback onLogout;
  final AppSettings settings;

  /// Tours were imported: the tours load again.
  final VoidCallback? onImported;

  /// The app's; tests pass their own.
  final Analytics? analytics;

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

  /// A choice of a setting in a sheet: the options, the current ticked.
  Future<T?> _pick<T>(String title, List<(T, String)> options, T current) => showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            for (final (value, label) in options)
              ListTile(
                title: Text(label),
                trailing: value == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    ),
  );

  String _paceText(AppLocalizations t, double p) => p == 1 ? t.accountPaceSignposts : '${(p * 100).round()}\u00a0%';

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    Widget group(List<Widget> rows) => Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, r) in rows.indexed) ...[if (i > 0) const Divider(height: 1, indent: 16), r],
        ],
      ),
    );
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1, color: muted.color),
      ),
    );
    Widget value(String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: muted),
        const Icon(Icons.chevron_right),
      ],
    );
    return FutureBuilder(
      future: _me,
      builder: (context, snap) {
        final me = snap.data;
        final initials = (me?.displayName ?? '')
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .take(2)
            .map((w) => w[0].toUpperCase())
            .join();
        // The header stays, as on the other tabs.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabHeader(t.navProfile),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      key: const Key('profile-mine'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      leading: CircleAvatar(radius: 26, child: Text(initials)),
                      title: Text(
                        me?.displayName ?? '',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      subtitle: me == null ? null : Text('@${me.username} · ${t.profileMine}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: me == null ? null : () => _push(UserScreen(api: widget.api, username: me.username)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  group([
                    ListTile(
                      key: const Key('friends'),
                      leading: const Icon(Icons.people_outline),
                      title: Text(t.friendsTitle),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if ((me?.friendRequests ?? 0) > 0) Badge.count(count: me!.friendRequests),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () async {
                        await Navigator.of(
                          context,
                        ).push(MaterialPageRoute<void>(builder: (_) => FriendsScreen(api: widget.api)));
                        // Requests answered there.
                        if (mounted) {
                          setState(() {
                            _me = widget.api.me();
                          });
                        }
                      },
                    ),
                    ImportTile(api: widget.api, onImported: widget.onImported),
                    // Apple Watch only; Health Connect on Android is to come (issue 8).
                    if (!Platform.isAndroid)
                      ListTile(
                        key: const Key('devices'),
                        leading: const Icon(Icons.watch_outlined),
                        title: Text(t.devicesTitle),
                        subtitle: Text(t.devicesSubtitle),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _push(DevicesScreen(api: widget.api, settings: widget.settings)),
                      ),
                  ]),
                  heading(t.settingsTitle),
                  group([
                    ValueListenableBuilder(
                      valueListenable: widget.settings.theme,
                      builder: (context, mode, _) {
                        final names = {
                          ThemeMode.system: t.themeSystem,
                          ThemeMode.light: t.themeLight,
                          ThemeMode.dark: t.themeDark,
                        };
                        return ListTile(
                          key: const Key('theme'),
                          title: Text(t.themeTitle),
                          trailing: value(names[mode]!),
                          onTap: () async {
                            final m = await _pick(t.themeTitle, [
                              for (final e in names.entries) (e.key, e.value),
                            ], mode);
                            if (m != null) await widget.settings.setTheme(m);
                          },
                        );
                      },
                    ),
                    ValueListenableBuilder(
                      valueListenable: widget.settings.locale,
                      builder: (context, locale, _) => ListTile(
                        key: const Key('language'),
                        title: Text(t.languageTitle),
                        trailing: value(_languages[locale?.languageCode] ?? t.themeSystem),
                        onTap: () async {
                          const auto = '';
                          final code = await _pick(t.languageTitle, [
                            (auto, t.themeSystem),
                            for (final e in _languages.entries) (e.key, e.value),
                          ], locale?.languageCode ?? auto);
                          if (code != null) await _language(code == auto ? null : code);
                        },
                      ),
                    ),
                    if (me != null)
                      ListTile(
                        key: const Key('pace'),
                        title: Text(t.accountPace),
                        subtitle: Text(t.accountPaceShort),
                        trailing: value('${(me.speedFactor * 100).round()}\u00a0%'),
                        onTap: () async {
                          final p = await _pick(t.accountPace, [
                            for (final p in {..._paces, me.speedFactor}.toList()..sort()) (p, _paceText(t, p)),
                          ], me.speedFactor);
                          if (p != null) _update(() => widget.api.updateMe(speedFactor: p));
                        },
                      ),
                    SwitchListTile(
                      key: const Key('profile-public'),
                      title: Text(t.profilePublic),
                      subtitle: Text(t.profilePublicHint),
                      value: me?.profilePublic ?? true,
                      onChanged: me == null ? null : (v) => _update(() => widget.api.updateMe(profilePublic: v)),
                    ),
                    if (me?.shareHikes case final share?)
                      SwitchListTile(
                        key: const Key('share-hikes'),
                        title: Text(t.shareHikes),
                        subtitle: Text(t.shareHikesHint),
                        value: share,
                        onChanged: (v) => _update(() => widget.api.updateMe(shareHikes: v)),
                      ),
                    if ((widget.analytics ?? Analytics.instance) case final analytics when analytics.active)
                      ValueListenableBuilder(
                        valueListenable: analytics.consent,
                        builder: (context, granted, _) => ListTile(
                          key: const Key('statistics'),
                          title: Text(t.statisticsTitle),
                          trailing: switch (granted) {
                            true => value(t.statisticsGranted),
                            false => value(t.statisticsDenied),
                            null => null,
                          },
                          onTap: () => askStatistics(context, analytics, widget.api.server),
                        ),
                      ),
                    ListTile(
                      key: const Key('notifications'),
                      title: Text(t.accountNotifications),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: me == null
                          ? null
                          : () => _push(
                              _NotificationsScreen(
                                api: widget.api,
                                me: me,
                                onChanged: (m) => setState(() {
                                  _me = Future.value(m);
                                }),
                              ),
                            ),
                    ),
                  ]),
                  heading(t.profileAccount),
                  group([
                    ListTile(
                      key: const Key('homes'),
                      leading: const Icon(Icons.home_outlined),
                      title: Text(t.homesTitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _push(HomesScreen(api: widget.api)),
                    ),
                    ListTile(
                      key: const Key('contacts'),
                      leading: const Icon(Icons.contact_mail_outlined),
                      title: Text(t.contactsTitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _push(ContactsScreen(api: widget.api)),
                    ),
                    ListTile(
                      key: const Key('blocked'),
                      leading: const Icon(Icons.block),
                      title: Text(t.blockedTitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _push(BlockedScreen(api: widget.api)),
                    ),
                  ]),
                  // Tokens are for programs on a computer: copying one on a phone is awkward.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      t.tokensOnWebsite,
                      key: const Key('tokens-on-website'),
                      style: muted.copyWith(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  group([
                    ListTile(
                      key: const Key('about'),
                      leading: const Icon(Icons.info_outline),
                      title: Text(t.aboutTitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _push(AboutScreen(server: widget.api.server)),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  // A lost phone: all other sessions end, this one stays.
                  TextButton(
                    key: const Key('logout-others'),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await widget.api.logoutOthers();
                        messenger.showSnackBar(SnackBar(content: Text(t.logoutOthersDone)));
                      } on Object {
                        messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
                      }
                    },
                    child: Text(t.logoutOthers),
                  ),
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
                  if (me != null && me.email.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(me.email, textAlign: TextAlign.center, style: muted.copyWith(fontSize: 12)),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The e-mails one gets: about comments and new followers.
class _NotificationsScreen extends StatefulWidget {
  const _NotificationsScreen({required this.api, required this.me, required this.onChanged});
  final Api api;
  final Me me;
  final ValueChanged<Me> onChanged;

  @override
  State<_NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<_NotificationsScreen> {
  late Me _me = widget.me;

  Future<void> _update(Future<Me> call) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final me = await call;
      widget.onChanged(me);
      if (mounted) setState(() => _me = me);
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(t.errorServer)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.accountNotifications)),
      body: Readable(
        child: ListView(
          children: [
            SwitchListTile(
              key: const Key('notify-comments'),
              title: Text(t.accountNotifyComments),
              value: _me.notifyComments,
              onChanged: (v) => _update(widget.api.updateMe(notifyComments: v)),
            ),
            SwitchListTile(
              key: const Key('notify-follows'),
              title: Text(t.accountNotifyFollows),
              value: _me.notifyFollows,
              onChanged: (v) => _update(widget.api.updateMe(notifyFollows: v)),
            ),
          ],
        ),
      ),
    );
  }
}
