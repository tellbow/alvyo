import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../navigation/recording.dart';
import '../navigation/live.dart';
import '../navigation/uploads.dart';
import '../offline/packs.dart';
import 'bottom_bar.dart';
import 'item_card.dart';
import 'journeys_list.dart';
import 'planner_screen.dart';
import 'profile_tab.dart';
import 'route_screen.dart';
import 'tag_chips.dart';
import 'watch_screen.dart';

/// The app after logging in: the user's routes (the saved ones when the
/// server cannot be reached), journeys, Apple Watch hikes and the account,
/// with the record button in the bar between them.
class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key, required this.api, required this.onLogout});
  final Api api;
  final VoidCallback onLogout;

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  int _tab = 0;
  late Future<(List<RouteSummary>, bool offline)> _routes = _load();

  Future<(List<RouteSummary>, bool)> _load() async {
    try {
      final routes = await widget.api.routes();
      _uploadHikes();
      return (routes, false);
    } catch (e) {
      if (e is ApiException && e.status == 401) {
        // The session ended (logged out elsewhere, or expired): log in again.
        WidgetsBinding.instance.addPostFrameCallback((_) => widget.onLogout());
      }
      if (e is ApiException && e.status < 500) rethrow;
      final saved = await (await PackStore.open()).savedRoutes();
      if (saved.isEmpty) rethrow;
      return (saved, true);
    }
  }

  /// Hikes recorded while offline go up now; the list then shows them.
  Future<void> _uploadHikes() async {
    final root = await Recording.defaultRoot();
    await LiveOutbox(root).flush(widget.api).catchError((_) => 0); // ends of shared hikes sent offline
    final n = await uploadHikes(widget.api, root).catchError((_) => 0);
    if (n > 0 && mounted) _reload();
  }

  void _reload() => setState(() {
    _routes = _load();
  });

  /// A hike in progress opens its route, where it goes on; without one, the
  /// routes are where a hike is started.
  Future<void> _record() async {
    final t = AppLocalizations.of(context);
    final active = await Recording.active(await Recording.defaultRoot());
    if (!mounted) return;
    if (active != null && Recording.before(active, active.routeId, widget.api.userId) == Before.resume) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RouteScreen(api: widget.api, id: active.routeId, title: active.title),
        ),
      );
      if (mounted) _reload();
      return;
    }
    setState(() => _tab = 0);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.recordHint(t.navStart))));
  }

  void _select(int tab) {
    // Hikes imported from the watch are routes now.
    if (_tab == 2 && tab != 2) _reload();
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final items = [
      BarItem(const Key('tab-routes'), Icons.map_outlined, t.routesTitle),
      BarItem(const Key('tab-journeys'), Icons.flag_outlined, t.journeysTitle),
      BarItem(const Key('watch'), Icons.watch_outlined, t.watchTitle),
      BarItem(const Key('tab-profile'), Icons.person_outline, t.navProfile),
    ];
    return Scaffold(
      extendBody: true,
      // The watch screen has its own bar.
      appBar: _tab == 2
          ? null
          : AppBar(
              title: Text(items[_tab].label),
              actions: [
                if (_tab == 0)
                  IconButton(
                    key: const Key('plan-route'),
                    tooltip: t.plannerTitle,
                    icon: const Icon(Icons.add_road),
                    onPressed: () async {
                      final planner = MaterialPageRoute<void>(builder: (_) => PlannerScreen(api: widget.api));
                      await Navigator.of(context).push(planner);
                      if (mounted) _reload(); // a saved route is in the list
                    },
                  ),
              ],
            ),
      body: switch (_tab) {
        0 => _routesList(t),
        1 => JourneysList(api: widget.api),
        // Built only when chosen: it asks for Apple Health.
        2 => WatchScreen(api: widget.api),
        _ => ProfileTab(api: widget.api, onLogout: widget.onLogout),
      },
      bottomNavigationBar: BottomBar(
        items: items,
        selected: _tab,
        onSelect: _select,
        recordLabel: t.navRecord,
        onRecord: _record,
      ),
    );
  }

  Widget _routesList(AppLocalizations t) => RefreshIndicator(
    onRefresh: () async => _reload(),
    child: FutureBuilder(
      future: _routes,
      builder: (context, snap) {
        if (snap.hasError) return ListView(children: [ListTile(title: Text(t.errorServer))]);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final (routes, offline) = snap.data!;
        if (routes.isEmpty) return ListView(children: [ListTile(title: Text(t.routesEmpty))]);
        return ListView.builder(
          itemCount: routes.length + (offline ? 1 : 0),
          itemBuilder: (context, i) {
            if (offline && i == 0) {
              return ListTile(
                key: const Key('routes-offline'),
                leading: const Icon(Icons.cloud_off),
                title: Text(t.routesOffline),
              );
            }
            final r = routes[offline ? i - 1 : i];
            return ItemCard(
              child: ListTile(
                title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                leading: r.hikedAt != null
                    ? Icon(Icons.hiking, semanticLabel: t.routesHiked(formatDate(r.hikedAt!)))
                    : null,
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text(
                      '${r.hikedAt != null ? '${t.routesHiked(formatDate(r.hikedAt!))} · ' : ''}'
                      '${formatDistance(r.totals.distanceM)} · ${formatDuration(r.totals.durationS)} · '
                      '↑ ${r.totals.ascentM.round()} m · ${formatSac(r.totals.sacGrade, r.totals.sacMax)}',
                    ),
                    if (r.tags.isNotEmpty) TagChips(r.tags),
                  ],
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
              ),
            );
          },
        );
      },
    ),
  );
}
