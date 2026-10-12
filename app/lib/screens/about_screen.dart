import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../map_credit.dart';

/// Where the source code is: the app's licence (AGPL-3.0) offers it with
/// every copy.
const sourceUrl = 'https://github.com/tellbow/alvyo';

/// What Alvyo is, the data it shows with their terms, its source code and
/// licences, and the privacy text and operator on the [server]'s website.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, required this.server});

  final String server;

  static Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget title(String text) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    return Scaffold(
      appBar: AppBar(title: Text(t.aboutTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(t.aboutIntro),
            title(t.aboutDataTitle),
            const DataSources(),
            const SizedBox(height: 8),
            Text(t.aboutSafety, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            title(t.aboutCodeTitle),
            Text(t.aboutCode),
            ListTile(
              key: const Key('about-source'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.code),
              title: Text(t.aboutSourceLink),
              onTap: () => _open(sourceUrl),
            ),
            ListTile(
              key: const Key('about-notice'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.article_outlined),
              title: Text(t.aboutNoticeLink),
              onTap: () => _open('$sourceUrl/blob/main/NOTICE'),
            ),
            ListTile(
              key: const Key('about-licenses'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: Text(t.aboutLicenses),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Alvyo',
                applicationLegalese: '© Adrian Berger and Alvyo contributors · AGPL-3.0-only',
              ),
            ),
            title(t.aboutPrivacy),
            ListTile(
              key: const Key('about-privacy'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(t.aboutPrivacy),
              subtitle: Text(t.aboutPrivacyHint),
              onTap: () => _open('$server/about#privacy'),
            ),
            ListTile(
              key: const Key('about-operator'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.mail_outline),
              title: Text(t.aboutOperator),
              onTap: () => _open('$server/about#operator'),
            ),
          ],
        ),
      ),
    );
  }
}
