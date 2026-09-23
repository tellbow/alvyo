import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../navigation/recording.dart';
import '../navigation/uploads.dart';
import '../offline/packs.dart';
import 'journeys_list.dart';
import 'route_screen.dart';
import 'watch_screen.dart';

/// The user's routes, and journeys in a second tab; the saved ones when the
/// server cannot be reached.
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
      final routes = await widget.api.routes();
      _uploadHikes();
      return (routes, false);
    } catch (e) {
      if (e is ApiException && e.status < 500) rethrow;
      final saved = await (await PackStore.open()).savedRoutes();
      if (saved.isEmpty) rethrow;
      return (saved, true);
    }
  }

  /// Hikes recorded while offline go up now; the list then shows them.
  Future<void> _uploadHikes() async {
    final n = await uploadHikes(widget.api, await Recording.defaultRoot()).catchError((_) => 0);
    if (n > 0 && mounted) _reload();
  }

  void _reload() => setState(() {
    _routes = _load();
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('odysgeh'),
          bottom: TabBar(
            tabs: [
              Tab(key: const Key('tab-routes'), text: t.routesTitle),
              Tab(key: const Key('tab-journeys'), text: t.journeysTitle),
            ],
          ),
          actions: [
            IconButton(
              key: const Key('watch'),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => WatchScreen(api: widget.api)));
                if (mounted) _reload();
              },
              icon: const Icon(Icons.watch),
              tooltip: t.watchTitle,
            ),
            IconButton(onPressed: widget.onLogout, icon: const Icon(Icons.logout), tooltip: t.logout),
          ],
        ),
        body: TabBarView(
          children: [
            RefreshIndicator(
              onRefresh: () async => _reload(),
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
                        leading: r.hikedAt != null
                            ? Icon(Icons.hiking, semanticLabel: t.routesHiked(formatDate(r.hikedAt!)))
                            : null,
                        subtitle: Text(
                          '${r.hikedAt != null ? '${t.routesHiked(formatDate(r.hikedAt!))} · ' : ''}'
                          '${formatDistance(r.totals.distanceM)} · ${formatDuration(r.totals.durationS)} · '
                          '↑ ${r.totals.ascentM.round()} m · ${formatSac(r.totals.sacGrade, r.totals.sacMax)}',
                        ),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RouteScreen(api: widget.api, id: r.id, title: r.title),
                            ),
                          );
                          // A hike may have been recorded and uploaded meanwhile.
                          if (mounted) _reload();
                        },
                      );
                    },
                  );
                },
              ),
            ),
            JourneysList(api: widget.api),
          ],
        ),
      ),
    );
  }
}
