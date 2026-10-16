import 'package:flutter/material.dart';

import '../errors.dart';
import '../api.dart';
import '../l10n/app_localizations.dart';
import '../offline/packs.dart';
import 'collections_screen.dart';
import 'discover_screen.dart';
import 'done.dart';
import 'journey_screen.dart';
import 'route_screen.dart';
import 'tab_header.dart';
import 'tiles.dart';
import 'wide.dart';

/// What the list shows: planned or hiked tours, or the collections.
enum TourSegment { planned, hiked, collections }

/// Which tours: all, routes, journeys, or those shared with one.
enum TourKind { all, routes, journeys, shared }

/// Touren (requirement 69): one's routes and journeys and those shared with
/// one in one list, the collections, and the map of them all. Saved ones
/// when the server cannot be reached.
class ToursTab extends StatefulWidget {
  const ToursTab({super.key, required this.api, this.onPlan, this.onRecord, this.onLoggedOut});
  final Api api;

  /// The next step of an empty list: to Planen, or recording.
  final VoidCallback? onPlan, onRecord;

  /// The session ended (logged out elsewhere, or expired).
  final VoidCallback? onLoggedOut;

  @override
  State<ToursTab> createState() => ToursTabState();
}

typedef _Tours = ({List<RouteSummary> routes, List<JourneySummary> journeys, Shared? shared, bool offline});

class ToursTabState extends State<ToursTab> {
  TourSegment _segment = TourSegment.planned;
  TourKind _kind = TourKind.all;
  bool _map = false;
  late Future<_Tours> _tours = _load();

  Future<_Tours> _load() async {
    final shared = widget.api.shared().then<Shared?>((s) => s, onError: (Object _) => null);
    try {
      final routes = await widget.api.routes();
      final journeys = await widget.api.journeys();
      return (routes: routes, journeys: journeys, shared: await shared, offline: false);
    } catch (e) {
      if (e is ApiException && e.status == 401) {
        WidgetsBinding.instance.addPostFrameCallback((_) => widget.onLoggedOut?.call());
      }
      if (e is ApiException && e.status < 500) rethrow;
      final store = await PackStore.open();
      final routes = await store.savedRoutes();
      final journeys = [for (final j in await store.savedJourneys()) JourneySummary.of(j)];
      if (routes.isEmpty && journeys.isEmpty) rethrow;
      return (routes: routes, journeys: journeys, shared: null, offline: true);
    }
  }

  /// Loads the lists again (after a hike was uploaded, a tour planned).
  void reload() => setState(() {
    _tours = _load();
  });

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lists = _segment != TourSegment.collections;
    // The map as wide as the screen.
    return Readable(
      on: !(lists && _map),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabHeader(
            t.toursTitle,
            action: lists
                ? HeaderAction(
                    key: const Key('tours-map'),
                    icon: _map ? Icons.list : Icons.map_outlined,
                    label: _map ? t.toursList : t.toursMap,
                    onPressed: () => setState(() => _map = !_map),
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<TourSegment>(
              key: const Key('tours-segment'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: TourSegment.planned, label: Text(t.doneFilterPlanned)),
                ButtonSegment(value: TourSegment.hiked, label: Text(t.doneFilterDone)),
                ButtonSegment(value: TourSegment.collections, label: Text(t.collectionsTitle)),
              ],
              selected: {_segment},
              onSelectionChanged: (v) => setState(() => _segment = v.first),
            ),
          ),
          if (lists && !_map)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
              child: Row(
                spacing: 8,
                children: [
                  for (final (k, label) in [
                    (TourKind.all, t.doneFilterAll),
                    (TourKind.routes, t.barRoutes),
                    (TourKind.journeys, t.toursJourneys),
                    (TourKind.shared, t.toursShared),
                  ])
                    ChoiceChip(
                      key: Key('tours-kind-${k.name}'),
                      label: Text(label),
                      selected: _kind == k,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Expanded(
            child: switch (_segment) {
              TourSegment.collections => CollectionsList(api: widget.api),
              _ when _map => DiscoverScreen(api: widget.api, mine: true, embedded: true),
              _ => _list(t),
            },
          ),
        ],
      ),
    );
  }

  Widget _list(AppLocalizations t) => RefreshIndicator(
    onRefresh: () async => reload(),
    child: FutureBuilder(
      future: _tours,
      builder: (context, snap) {
        if (snap.hasError) return ListView(children: [ListTile(title: Text(errorText(t, snap.error)))]);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final tours = snap.data!;
        final filter = _segment == TourSegment.hiked ? DoneFilter.done : DoneFilter.planned;
        final own = _kind != TourKind.shared;
        final others = _kind == TourKind.all || _kind == TourKind.shared;
        final routes = _kind != TourKind.journeys;
        final journeys = _kind != TourKind.routes;
        final cards = <Widget>[
          if (own && routes)
            for (final r in tours.routes)
              if (passesDone(filter, r.doneOn))
                RouteTile(
                  route: r,
                  onTap: () => _open(RouteScreen(api: widget.api, id: r.id, title: r.title)),
                ),
          if (own && journeys)
            for (final j in tours.journeys)
              if (passesDone(filter, j.doneOn))
                JourneyTile(
                  journey: j,
                  onTap: () => _open(JourneyScreen(api: widget.api, id: j.id, title: j.title)),
                ),
          if (others && routes)
            for (final r in tours.shared?.routes ?? const <RouteSummary>[])
              if (passesDone(filter, r.doneOn))
                RouteTile(
                  route: r,
                  owner: r.owner,
                  onTap: () => _open(RouteScreen(api: widget.api, id: r.id, title: r.title)),
                ),
          if (others && journeys)
            for (final j in tours.shared?.journeys ?? const <JourneySummary>[])
              if (passesDone(filter, j.doneOn))
                JourneyTile(
                  journey: j,
                  owner: j.owner,
                  onTap: () => _open(JourneyScreen(api: widget.api, id: j.id, title: j.title)),
                ),
        ];
        final nothing = tours.routes.isEmpty && tours.journeys.isEmpty && (tours.shared?.routes.isEmpty ?? true);
        return ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            if (tours.offline)
              ListTile(
                key: const Key('tours-offline'),
                leading: const Icon(Icons.cloud_off),
                title: Text(t.routesOffline),
              ),
            ...cards,
            if (cards.isEmpty)
              switch (null) {
                _ when nothing || _kind == TourKind.all =>
                  _segment == TourSegment.hiked
                      ? EmptyHint(
                          key: const Key('tours-empty'),
                          icon: Icons.hiking,
                          text: t.toursEmptyHiked,
                          action: t.navRecord,
                          onAction: widget.onRecord,
                        )
                      : EmptyHint(
                          key: const Key('tours-empty'),
                          icon: Icons.route_outlined,
                          text: t.toursEmptyPlanned,
                          action: t.toursPlanAction,
                          onAction: widget.onPlan,
                        ),
                _ => EmptyHint(key: const Key('tours-empty'), text: t.doneFilterNone),
              },
          ],
        );
      },
    ),
  );
}
