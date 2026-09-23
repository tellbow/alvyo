import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../offline/packs.dart';
import 'route_screen.dart';

/// The user's routes; the saved ones when the server cannot be reached.
class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key, required this.api, required this.onLogout});
  final Api api;
  final VoidCallback onLogout;

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  late Future<(List<RouteSummary>, bool offline)> _routes = _load();

  Future<(List<RouteSummary>, bool)> _load() async {
    try {
      return (await widget.api.routes(), false);
    } catch (e) {
      if (e is ApiException && e.status < 500) rethrow;
      final saved = await (await PackStore.open()).savedRoutes();
      if (saved.isEmpty) rethrow;
      return (saved, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.routesTitle),
        actions: [IconButton(onPressed: widget.onLogout, icon: const Icon(Icons.logout), tooltip: t.logout)],
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _routes = _load()),
        child: FutureBuilder(
          future: _routes,
          builder: (context, snap) {
            if (snap.hasError) return ListView(children: [ListTile(title: Text(t.errorServer))]);
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final (routes, offline) = snap.data!;
            if (routes.isEmpty) return ListView(children: [ListTile(title: Text(t.routesEmpty))]);
            return ListView.separated(
              itemCount: routes.length + (offline ? 1 : 0),
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                if (offline && i == 0) {
                  return ListTile(
                    key: const Key('routes-offline'),
                    leading: const Icon(Icons.cloud_off),
                    title: Text(t.routesOffline),
                  );
                }
                final r = routes[offline ? i - 1 : i];
                return ListTile(
                  title: Text(r.title),
                  subtitle: Text(
                    '${formatDistance(r.totals.distanceM)} · ${formatDuration(r.totals.durationS)} · '
                    '↑ ${r.totals.ascentM.round()} m · ${formatSac(r.totals.sacGrade, r.totals.sacMax)}',
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RouteScreen(api: widget.api, id: r.id, title: r.title),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
