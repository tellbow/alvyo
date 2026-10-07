import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/app_localizations.dart';
import '../navigation/live.dart';
import '../navigation/recording.dart';
import '../navigation/uploads.dart';
import '../settings.dart';
import '../watch/importer.dart';
import 'bottom_bar.dart';
import 'discover_tab.dart';
import 'navigate_screen.dart';
import 'plan_tab.dart';
import 'profile_tab.dart';
import 'record_screen.dart';
import 'route_screen.dart';
import 'tours_tab.dart';
import 'watch_screen.dart';

/// The app after logging in (requirement 69): Entdecken (where to?),
/// Planen (how?), the record button (go!), Touren (what do I have?) and
/// Profil.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.onLogout,
    this.settings,
    this.record,
    @visibleForTesting this.planModes,
    @visibleForTesting this.watch,
  });
  final Api api;
  final VoidCallback onLogout;

  /// The app's; tests pass their own.
  final AppSettings? settings;

  /// For tests: stands in for the recording screen (GPS and map).
  final Widget Function()? record;

  /// For tests: stands in for the planning screens (MapLibre).
  final Widget Function(PlanMode mode, VoidCallback saved)? planModes;

  /// For tests: imports from a fake Apple Health.
  final WatchImporter? watch;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// The tabs, in the bar's order.
enum HomeTab { discover, plan, tours, profile }

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  HomeTab _tab = HomeTab.discover;

  /// Tabs are built when first shown (Planen's map not before), then kept.
  final _shown = {HomeTab.discover};
  final _tours = GlobalKey<ToursTabState>();
  final _plan = GlobalKey<PlanTabState>();

  late final _settings = widget.settings ?? AppSettings.instance;
  late final _watch = widget.watch ?? WatchImporter(widget.api);
  DateTime? _watchChecked;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkSession();
    _uploadHikes();
    WidgetsBinding.instance.addPostFrameCallback((_) => _importWatch());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _importWatch();
  }

  /// New Apple Watch hikes become routes when the app opens, if switched
  /// on (Profil › Verbundene Geräte); at most every 10 minutes.
  Future<void> _importWatch() async {
    await _settings.loaded;
    final since = _settings.watchAutoSince.value;
    final last = _watchChecked;
    if (since == null || !mounted || (last != null && DateTime.now().difference(last).inMinutes < 10)) return;
    _watchChecked = DateTime.now();
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final count = await _watch.importNew(since, (w) => watchTitle(t, w)).catchError((_) => 0);
    if (count == 0 || !mounted) return;
    messenger.showSnackBar(SnackBar(key: const Key('watch-imported'), content: Text(t.devicesWatchImported(count))));
    _tours.currentState?.reload();
  }

  /// The session ended (logged out elsewhere, or expired): log in again.
  /// Offline the app goes on with what it saved.
  Future<void> _checkSession() async {
    try {
      await widget.api.me();
    } on ApiException catch (e) {
      if (e.status == 401 && mounted) widget.onLogout();
    } on Object {
      // offline
    }
  }

  /// Hikes recorded while offline go up now; the tours then show them.
  Future<void> _uploadHikes() async {
    try {
      final root = await Recording.defaultRoot();
      await LiveOutbox(root).flush(widget.api).catchError((_) => 0); // ends of shared hikes sent offline
      final routes = await uploadHikes(widget.api, root).catchError((_) => <String, String?>{});
      if (routes.values.any((id) => id != null) && mounted) _tours.currentState?.reload();
    } on Object {
      // tried again at the next start
    }
  }

  /// Records a hike; one on a route still being recorded goes on there.
  /// The finished hike is uploaded and opened as a route.
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
      if (mounted) _tours.currentState?.reload();
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
    _tours.currentState?.reload();
    if (routes[summary.id] case final id?) {
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => RouteScreen(api: widget.api, id: id, title: t.recordTitle),
        ),
      );
    }
  }

  void _select(HomeTab tab) => setState(() {
    _tab = tab;
    _shown.add(tab);
  });

  /// Opens Planen in one of its modes («Wie weit komme ich?» on Entdecken).
  void _planIn(PlanMode mode) {
    _select(HomeTab.plan);
    WidgetsBinding.instance.addPostFrameCallback((_) => _plan.currentState?.show(mode));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final items = [
      BarItem(const Key('tab-discover'), Icons.explore_outlined, t.barDiscover),
      BarItem(const Key('tab-plan'), Icons.route_outlined, t.barPlan),
      BarItem(const Key('tab-tours'), Icons.filter_none_outlined, t.barTours),
      BarItem(const Key('tab-profile'), Icons.person_outline, t.navProfile),
    ];
    return Scaffold(
      extendBody: true,
      // Every tab is kept: switching back keeps its scroll and its state.
      body: IndexedStack(
        index: _tab.index,
        children: [
          for (final tab in HomeTab.values)
            if (!_shown.contains(tab)) const SizedBox.shrink() else _build(tab),
        ],
      ),
      bottomNavigationBar: BottomBar(
        items: items,
        selected: _tab.index,
        onSelect: (i) => _select(HomeTab.values[i]),
        recordLabel: t.navRecord,
        onRecord: _record,
      ),
    );
  }

  Widget _build(HomeTab tab) => switch (tab) {
    HomeTab.discover => DiscoverTab(api: widget.api, onPlan: _planIn),
    HomeTab.plan => PlanTab(
      key: _plan,
      api: widget.api,
      modes: widget.planModes,
      onSaved: () => _tours.currentState?.reload(),
    ),
    HomeTab.tours => ToursTab(
      key: _tours,
      api: widget.api,
      onPlan: () => _select(HomeTab.plan),
      onRecord: _record,
      onLoggedOut: widget.onLogout,
    ),
    HomeTab.profile => SafeArea(
      bottom: false,
      child: ProfileTab(api: widget.api, onLogout: widget.onLogout, settings: _settings),
    ),
  };
}
