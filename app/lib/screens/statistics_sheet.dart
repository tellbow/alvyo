import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../analytics.dart';
import '../l10n/app_localizations.dart';

/// Asks whether Google Analytics may measure how the app is used, both
/// answers alike, as the website's banner. Closed without an answer, it
/// asks again at the next start.
Future<void> askStatistics(BuildContext context, Analytics analytics, String server) async {
  final t = AppLocalizations.of(context);
  final granted = await showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          key: const Key('statistics-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.statisticsTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(t.statisticsAsk),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => launchUrl(Uri.parse('$server/about#statistics'), mode: LaunchMode.externalApplication),
                child: Text(t.aboutPrivacy),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  key: const Key('statistics-decline'),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(t.statisticsDecline),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('statistics-accept'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(t.statisticsAccept),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (granted != null) await analytics.setConsent(granted);
}
