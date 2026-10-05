import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/app_localizations.dart';
import '../navigation/recording.dart';
import '../navigation/live.dart';
import '../navigation/uploads.dart';
import '../offline/packs.dart';
import '../settings.dart';
import 'bottom_bar.dart';
import 'discover_screen.dart';
import 'done.dart';
import 'feed_tab.dart';
import 'journeys_list.dart';
import 'navigate_screen.dart';
import 'planner_screen.dart';
import 'profile_tab.dart';
import 'record_screen.dart';
import 'route_screen.dart';
import 'tiles.dart';
import 'watch_screen.dart';

/// The app after logging in: the user's routes (the saved ones when the
/// server cannot be reached) and those shared with them, journeys, the feed
/// and the account, with the record button in the bar between them.
class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key, required this.api, required this.onLogout, this.settings, this.record});
  final Api api;
  final VoidCallback onLogout;

  /// The app's; tests pass their own.
  final AppSettings? settings;

  /// For tests: stands in for the recording screen (GPS and map).
  final Widget Function()? record;

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  DoneFilter _done = DoneFilter.all;
  int _tab = 0;
  late Future<(List<RouteSummary>, bool offline)> _routes = _load();
  late Future<List<RouteSummary>> _shared = _loadShared();

  Future<List<RouteSummary>> _loadShared() =>
      widget.api.shared().then((s) => s.routes, onError: (Object _) => <RouteSummary>[]);

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
    final routes = await uploadHikes(widget.api, root).catchError((_) => <String, String?>{});
    if (routes.values.any((id) => id != null) && mounted) _reload();
  }

  void _reload() => setState(() {
    _routes = _load();
    _shared = _loadShared();
  });

  /// Records a hike without a route; one on a route still being recorded
  /// goes on there. The finished hike is uploaded and opened as a route.
  Future<void> _record() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final root = await Recording.defaultRoot();
    final active = await Recording.active(root);
    if (!mounted) return;
    if (active?.routeId case final id? when Recording.before(active, id, widget.api.userId) == Before.resume) {
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => RouteScreen(api: widget.api, id: id, title: active!.title),
        ),
      );
      if (mounted) _reload();
      return;
    }
    final summary = await navigator.push<HikeSummary>(
      MaterialPageRoute(builder: (_) => widget.record?.call() ?? RecordScreen(api: widget.api)),
    );
    if (summary == null || !mounted) return;
    final routes = await uploadHikes(widget.api, root).catchError((_) => <String, String?>{});
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(key: const Key('nav-saved'), summary.message(t, routes)),
        duration: const Duration(seconds: 8),
      ),
    );
    _reload();
    if (routes[summary.id] case final id?) {
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => RouteScreen(api: widget.api, id: id, title: t.recordTitle),
        ),
      );
    }
  }

  void _select(int tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final items = [
      BarItem(const Key('tab-routes'), Icons.map_outlined, t.barRoutes),
      BarItem(const Key('tab-journeys'), Icons.flag_outlined, t.barJourneys),
      BarItem(const Key('tab-feed'), Icons.dynamic_feed_outlined, t.navFeed),
      BarItem(const Key('tab-profile'), Icons.person_outline, t.navProfile),
    ];
    final titles = [t.routesTitle, t.journeysTitle, t.navFeed, t.navProfile];
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Text(titles[_tab]),
        actions: [
          if (_tab == 0) ...[
            IconButton(
              key: const Key('discover'),
              tooltip: t.discoverAction,
              icon: const Icon(Icons.explore_outlined),
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => DiscoverScreen(api: widget.api))),
            ),
            IconButton(
              key: const Key('watch'),
              tooltip: t.watchTitle,
              icon: const Icon(Icons.watch_outlined),
              onPressed: () async {
                // Built only when chosen: it asks for Apple Health.
                await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WatchScreen(api: widget.api)));
                if (mounted) _reload(); // imported hikes are routes now
              },
            ),
            TextButton.icon(
              key: const Key('plan-route'),
              icon: const Icon(Icons.add),
              label: Text(t.planAction, semanticsLabel: t.plannerTitle),
              onPressed: () async {
                final planner = MaterialPageRoute<void>(builder: (_) => PlannerScreen(api: widget.api));
                await Navigator.of(context).push(planner);
                if (mounted) _reload(); // a saved route is in the list
              },
            ),
          ],
        ],
      ),
      body: switch (_tab) {
        0 => _routesList(t),
        1 => JourneysList(api: widget.api),
        2 => FeedTab(api: widget.api),
        _ => ProfileTab(api: widget.api, onLogout: widget.onLogout, settings: widget.settings ?? AppSettings.instance),
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
        return FutureBuilder(
          future: offline ? Future.value(<RouteSummary>[]) : _shared,
          builder: (context, sharedSnap) {
            final shared = [
              for (final r in sharedSnap.data ?? const <RouteSummary>[])
                if (passesDone(_done, r.doneOn)) r,
            ];
            final shown = [
              for (final r in routes)
                if (passesDone(_done, r.doneOn)) r,
            ];
            return ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                if (offline)
                  ListTile(
                    key: const Key('routes-offline'),
                    leading: const Icon(Icons.cloud_off),
                    title: Text(t.routesOffline),
                  ),
                if (routes.isEmpty)
                  ListTile(title: Text(t.routesEmpty))
                else ...[
                  DoneFilterBar(value: _done, onChanged: (f) => setState(() => _done = f)),
                  if (shown.isEmpty) ListTile(title: Text(t.doneFilterNone)),
                ],
                for (final r in shown) RouteTile(route: r, onTap: () => _open(r)),
                if (shared.isNotEmpty) ListHeading(t.sharedTitle),
                for (final r in shared) RouteTile(route: r, owner: r.owner, onTap: () => _open(r)),
              ],
            );
          },
        );
      },
    ),
  );

  Future<void> _open(RouteSummary r) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RouteScreen(api: widget.api, id: r.id, title: r.title),
      ),
    );
    // A hike may have been recorded and uploaded meanwhile.
    if (mounted) _reload();
  }
}
