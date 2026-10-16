import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/app_localizations.dart';
import '../settings.dart';
import 'watch_screen.dart';
import 'wide.dart';

/// Verbundene Geräte (requirement 69): the Apple Watch, its hikes imported
/// by hand or automatically when the app opens.
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key, required this.api, required this.settings});
  final Api api;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.devicesTitle)),
      body: Readable(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.watch_outlined),
                    title: Text(t.devicesWatch),
                    subtitle: Text(t.devicesWatchHint),
                  ),
                  const Divider(height: 1),
                  ValueListenableBuilder(
                    valueListenable: settings.watchAutoSince,
                    builder: (context, since, _) => SwitchListTile(
                      key: const Key('watch-auto'),
                      title: Text(t.devicesWatchAuto),
                      subtitle: Text(t.devicesWatchAutoHint),
                      value: since != null,
                      onChanged: settings.setWatchAuto,
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    key: const Key('watch-pick'),
                    title: Text(t.devicesWatchPick),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WatchScreen(api: api))),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
