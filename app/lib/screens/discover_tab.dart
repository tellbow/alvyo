import 'dart:async';

import 'package:flutter/material.dart';

import '../errors.dart';
import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../navigation/gps.dart';
import 'discover_screen.dart';
import 'feed_tab.dart';
import 'friends_screen.dart';
import 'peaks_screen.dart';
import 'plan_tab.dart';
import 'tab_header.dart';
import 'tiles.dart';

/// Entdecken (requirement 69): where to? A search for places and summits,
/// the tools for around one, the tours of people one follows and public
/// tours nearby.
class DiscoverTab extends StatefulWidget {
  const DiscoverTab({super.key, required this.api, required this.onPlan, this.position});
  final Api api;

  /// Opens Planen in a mode («Wie weit komme ich?»).
  final ValueChanged<PlanMode> onPlan;

  /// For tests: where the phone is.
  final Future<LonLat?> Function()? position;

  @override
  State<DiscoverTab> createState() => _DiscoverTabState();
}

/// How many tours each part shows; «Alle» and «Karte» show the rest.
const _shown = 3;

class _DiscoverTabState extends State<DiscoverTab> {
  late Future<List<FeedItem>> _feed = _loadFeed();
  late Future<({LonLat? at, List<DiscoverItem> items})> _nearby = _loadNearby();
  final _search = TextEditingController();
  List<FoundPlace>? _found;
  Timer? _typing;
  int _asked = 0;

  Future<List<FeedItem>> _loadFeed() => widget.api.feed().then((p) => p.items);

  /// Public tours in about 15 km around the phone; none without a position.
  Future<({LonLat? at, List<DiscoverItem> items})> _loadNearby() async {
    final at = await (widget.position ?? knownPosition)();
    if (at == null) return (at: null, items: <DiscoverItem>[]);
    const dLat = 0.14, dLon = 0.2;
    final found = await widget.api.discover((
      west: at.lon - dLon,
      south: at.lat - dLat,
      east: at.lon + dLon,
      north: at.lat + dLat,
    ));
    return (at: at, items: found.items);
  }

  Future<void> _reload() async {
    setState(() {
      _feed = _loadFeed();
      _nearby = _loadNearby();
    });
    await Future.wait([
      _feed.catchError((_) => <FeedItem>[]),
      _nearby.catchError((_) => (at: null, items: <DiscoverItem>[])),
    ]);
  }

  @override
  void dispose() {
    _typing?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _searchChanged(String q) {
    _typing?.cancel();
    if (q.trim().length < 2) {
      setState(() => _found = null);
      return;
    }
    _typing = Timer(const Duration(milliseconds: 300), () async {
      final asked = ++_asked;
      final near = await _nearby.then((n) => n.at, onError: (Object _) => null);
      final found = await widget.api.searchPlaces(q.trim(), near: near).catchError((_) => <FoundPlace>[]);
      if (mounted && asked == _asked) setState(() => _found = found);
    });
  }

  Future<void> _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final found = _found;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabHeader(t.barDiscover),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            key: const Key('discover-search'),
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: t.discoverSearchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: found == null
                  ? null
                  : IconButton(
                      tooltip: t.cancel,
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        _searchChanged('');
                      },
                    ),
            ),
            onChanged: _searchChanged,
          ),
        ),
        Expanded(child: found != null ? _results(t, found) : _sections(t)),
      ],
    );
  }

  /// Places and summits found: each opens the map there.
  Widget _results(AppLocalizations t, List<FoundPlace> found) => ListView(
    padding: const EdgeInsets.only(bottom: 120),
    children: [
      if (found.isEmpty) EmptyHint(text: t.discoverSearchNone),
      for (final p in found)
        ListTile(
          key: Key('found-${p.lon}-${p.lat}'),
          // Names are swisstopo's: summits, passes, valleys …
          leading: Icon(p.kind == 'name' ? Icons.landscape_outlined : Icons.place_outlined),
          title: Text(p.name),
          subtitle: p.detail.isEmpty ? null : Text(p.detail),
          onTap: () => _push(DiscoverScreen(api: widget.api, start: (lon: p.lon, lat: p.lat))),
        ),
    ],
  );

  Widget _sections(AppLocalizations t) => RefreshIndicator(
    onRefresh: _reload,
    child: ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                Expanded(
                  child: _ToolCard(
                    key: const Key('tool-reach'),
                    icon: Icons.radar,
                    title: t.reachTitle,
                    text: t.discoverReachHint,
                    onTap: () => widget.onPlan(PlanMode.reach),
                  ),
                ),
                Expanded(
                  child: _ToolCard(
                    key: const Key('tool-peaks'),
                    icon: Icons.filter_hdr_outlined,
                    title: t.discoverPeaks,
                    text: t.discoverPeaksHint,
                    onTap: () => _push(PeaksScreen(api: widget.api)),
                  ),
                ),
              ],
            ),
          ),
        ),
        SectionHeading(
          t.discoverFollowing,
          action: HeaderAction(
            key: const Key('feed-all'),
            label: t.discoverAll,
            onPressed: () => _push(
              Scaffold(
                appBar: AppBar(title: Text(t.discoverFollowing)),
                body: FeedTab(api: widget.api),
              ),
            ),
          ),
        ),
        FutureBuilder(
          future: _feed,
          builder: (context, snap) {
            if (snap.hasError) return ListTile(title: Text(errorText(t, snap.error)));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            if (snap.data!.isEmpty) {
              return EmptyHint(
                key: const Key('feed-empty'),
                text: t.discoverFollowingEmpty,
                action: t.friendsTitle,
                onAction: () => _push(FriendsScreen(api: widget.api)),
              );
            }
            return Column(
              children: [
                for (final i in snap.data!.take(_shown))
                  OtherTile(
                    key: Key('feed-${i.id}'),
                    journey: i.kind == 'journey',
                    title: i.title,
                    owner: i.ownerName,
                    extra: formatDate(i.publishedAt),
                    distanceM: i.distanceM,
                    durationS: i.durationS,
                    ascentM: i.ascentM,
                    sacGrade: i.sacGrade,
                    sacMax: i.sacMax,
                    stages: i.stages,
                    onTap: () => openItem(context, widget.api, journey: i.kind == 'journey', id: i.id, title: i.title),
                  ),
              ],
            );
          },
        ),
        SectionHeading(
          t.discoverNearby,
          action: HeaderAction(
            key: const Key('nearby-map'),
            label: t.toursMap,
            onPressed: () => _push(DiscoverScreen(api: widget.api)),
          ),
        ),
        FutureBuilder(
          future: _nearby,
          builder: (context, snap) {
            if (snap.hasError) return ListTile(title: Text(errorText(t, snap.error)));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final (:at, :items) = snap.data!;
            if (at == null) {
              return EmptyHint(
                key: const Key('nearby-no-position'),
                text: t.discoverNearbyNoPosition,
                action: t.discoverNearbyAllow,
                onAction: () async {
                  if (await locationAllowed()) await _reload();
                },
              );
            }
            if (items.isEmpty) {
              return EmptyHint(
                key: const Key('nearby-empty'),
                text: t.discoverNearbyEmpty,
                action: t.toursMap,
                onAction: () => _push(DiscoverScreen(api: widget.api)),
              );
            }
            return Column(
              children: [
                for (final it in items.take(_shown))
                  OtherTile(
                    key: Key('nearby-${it.id}'),
                    journey: it.kind == 'journey',
                    title: it.title,
                    owner: it.owner,
                    official: it.official,
                    distanceM: it.distanceM,
                    durationS: it.durationS,
                    ascentM: it.ascentM,
                    sacGrade: it.sacGrade,
                    sacMax: it.sacMax,
                    stages: it.stages,
                    onTap: () =>
                        openItem(context, widget.api, journey: it.kind == 'journey', id: it.id, title: it.title),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

/// One of Entdecken's tools: an icon, a name and what it does.
class _ToolCard extends StatelessWidget {
  const _ToolCard({super.key, required this.icon, required this.title, required this.text, required this.onTap});
  final IconData icon;
  final String title, text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: 4),
              Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
