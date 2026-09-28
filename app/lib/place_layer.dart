import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:maplibre/maplibre.dart';

import 'api.dart';
import 'format.dart';
import 'l10n/app_localizations.dart';

/// The places a map can show, each switched on in the layer menu.
enum PlaceGroup { huts, lodging, pois }

const _groupKinds = {
  PlaceGroup.huts: ['hut'],
  PlaceGroup.lodging: ['hotel', 'campsite'],
  PlaceGroup.pois: ['peak', 'viewpoint', 'waterfall', 'water', 'shelter'],
};

/// Below these zooms, too many points.
const _groupMinZoom = {PlaceGroup.huts: 8.0, PlaceGroup.lodging: 10.0, PlaceGroup.pois: 12.0};

/// The kinds to fetch for the [shown] groups at [zoom].
List<String> placeKinds(Set<PlaceGroup> shown, double zoom) => [
  for (final g in PlaceGroup.values)
    if (shown.contains(g) && zoom >= _groupMinZoom[g]!) ..._groupKinds[g]!,
];

/// Which places the maps show: off until switched on, remembered in the
/// Keychain like the session.
class PlaceSettings {
  PlaceSettings({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  /// Shared by all maps, so a switch holds on the next screen too.
  static final instance = PlaceSettings();

  static const _key = 'map-places';
  final FlutterSecureStorage _storage;
  final shown = ValueNotifier<Set<PlaceGroup>>({});
  late final Future<void> loaded = _load();

  Future<void> _load() async {
    try {
      final v = await _storage.read(key: _key) ?? '';
      shown.value = {
        for (final name in v.split(','))
          for (final g in PlaceGroup.values)
            if (g.name == name) g,
      };
    } on Object {
      // no Keychain (tests): all off
    }
  }

  Future<void> toggle(PlaceGroup g) async {
    await loaded;
    shown.value = shown.value.contains(g) ? ({...shown.value}..remove(g)) : {...shown.value, g};
    try {
      await _storage.write(key: _key, value: shown.value.map((g) => g.name).join(','));
    } on Object {
      // not remembered, still switched
    }
  }
}

/// Huts (red), hotels (blue) and campsites (green) of the visible area on a
/// MapLibre map, from `GET /places/in-view`. The screen calls [addTo] when
/// its style has loaded, before adding its own layers (which then lie on
/// top), and passes the map's events to [onEvent]. Without a connection what
/// is shown stays.
class PlaceLayer {
  PlaceLayer(this.api, {required this.onTap, PlaceSettings? settings}) : settings = settings ?? PlaceSettings.instance {
    this.settings.shown.addListener(_switched);
  }

  final Api api;
  final void Function(Pin pin) onTap;
  final PlaceSettings settings;

  static const _id = 'places';
  MapController? _map;
  StyleController? _style;
  Timer? _timer;

  /// Counts the requests: only the latest answer is shown.
  int _asked = 0;
  List<Pin> _shown = const [];

  Future<void> addTo(StyleController style) async {
    _style = null;
    await style.addSource(GeoJsonSource(id: _id, data: _geojson(_shown), attribution: '© OpenStreetMap contributors'));
    await style.addLayer(
      const CircleStyleLayer(
        id: _id,
        sourceId: _id,
        paint: {
          'circle-radius': [
            'interpolate',
            ['linear'],
            ['zoom'],
            8,
            5,
            14,
            8,
          ],
          'circle-color': [
            'match',
            ['get', 'kind'],
            'hut',
            '#b91c1c',
            'campsite',
            '#15803d',
            'peak',
            '#57534e',
            'viewpoint',
            '#7c3aed',
            'waterfall',
            '#0e7490',
            'water',
            '#0284c7',
            'shelter',
            '#a16207',
            '#1d4ed8',
          ],
          'circle-stroke-color': '#ffffff',
          'circle-stroke-width': 1.5,
        },
      ),
    );
    _style = style;
    await settings.loaded;
    _load(now: true);
  }

  void onEvent(MapEvent e) {
    switch (e) {
      case MapEventMapCreated(:final mapController):
        _map = mapController;
      case MapEventCameraIdle():
        _load();
      case MapEventClick(:final screenPoint):
        _tap(screenPoint);
      default:
    }
  }

  void dispose() {
    settings.shown.removeListener(_switched);
    _timer?.cancel();
    _asked++;
  }

  /// Switched off: gone at once; switched on: fetched.
  void _switched() {
    final kinds = {for (final g in settings.shown.value) ..._groupKinds[g]!};
    _show(_shown.where((p) => kinds.contains(p.kind)).toList());
    _load(now: true);
  }

  /// Once the map rests a moment.
  void _load({bool now = false}) {
    _timer?.cancel();
    _timer = Timer(now ? Duration.zero : const Duration(milliseconds: 300), () async {
      final map = _map;
      if (map == null || _style == null) return;
      final asked = ++_asked;
      final kinds = placeKinds(settings.shown.value, map.getCamera().zoom);
      if (kinds.isEmpty) {
        _show(const []);
        return;
      }
      try {
        final b = map.getVisibleRegion();
        final pins = await api.placesInView((
          west: b.longitudeWest,
          south: b.latitudeSouth,
          east: b.longitudeEast,
          north: b.latitudeNorth,
        ), kinds);
        if (asked == _asked) _show(pins);
      } on Object {
        // offline: keep what is shown
      }
    });
  }

  void _show(List<Pin> pins) {
    _shown = pins;
    _style?.updateGeoJsonSource(id: _id, data: _geojson(pins)).catchError((_) {});
  }

  /// A finger is wider than a dot.
  void _tap(Offset at) {
    final map = _map;
    if (map == null || _style == null || _shown.isEmpty) return;
    final found = map.featuresInRect(Rect.fromCircle(center: at, radius: 16), layerIds: [_id]);
    if (found.isEmpty) return;
    final id = found.first.properties['id'];
    if (_shown.where((p) => p.id == id).firstOrNull case final pin?) onTap(pin);
  }

  static String _geojson(List<Pin> pins) => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final p in pins)
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [p.lon, p.lat],
          },
          'properties': {'id': p.id, 'kind': p.kind},
        },
    ],
  });
}

/// The small button on a map that opens the layer menu.
class PlaceLayerButton extends StatelessWidget {
  const PlaceLayerButton({super.key, this.settings});
  final PlaceSettings? settings;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final s = settings ?? PlaceSettings.instance;
    return FloatingActionButton.small(
      key: const Key('map-layers'),
      heroTag: null, // several on a stack of screens
      tooltip: t.mapLayers,
      onPressed: () async {
        await s.loaded;
        if (!context.mounted) return;
        await showModalBottomSheet<void>(
          context: context,
          builder: (context) => SafeArea(
            child: ValueListenableBuilder(
              valueListenable: s.shown,
              builder: (context, shown, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (g, label) in [
                    (PlaceGroup.huts, t.mapHuts),
                    (PlaceGroup.lodging, t.mapLodging),
                    (PlaceGroup.pois, t.mapPois),
                  ])
                    SwitchListTile(
                      key: Key('map-layer-${g.name}'),
                      title: Text(label),
                      value: shown.contains(g),
                      onChanged: (_) => s.toggle(g),
                    ),
                ],
              ),
            ),
          ),
        );
      },
      child: const Icon(Icons.layers_outlined),
    );
  }
}

/// What kind of place it is, as specific as the data allows.
String placeKindText(AppLocalizations t, String kind, String detail) => switch (kind) {
  'hut' when detail == 'wilderness_hut' => t.placeWildernessHut,
  'hut' => t.placeHut,
  'hotel' => t.placeHotel,
  'campsite' => t.placeCampsite,
  'pt_stop' => detail.isNotEmpty ? detail : t.placePtStop,
  'peak' => detail.isNotEmpty ? '${t.poiPeak} · ${formatHeight(double.parse(detail))}' : t.poiPeak,
  'viewpoint' => t.poiViewpoint,
  'waterfall' => t.poiWaterfall,
  'water' => t.poiWater,
  'shelter' => t.poiShelter,
  'address' => t.placeAddress,
  _ => detail, // a name from the national map: its kind and municipality
};

/// A website only when it is an http(s) address: OSM holds free text.
String? webLink(String url) {
  final u = Uri.tryParse(url.trim());
  return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty ? u.toString() : null;
}

/// Name, kind and website of a tapped place; [actions] below, e.g. to add it
/// to a planned route.
Future<void> showPlace(BuildContext context, Pin pin, {List<Widget> actions = const []}) {
  final t = AppLocalizations.of(context);
  final theme = Theme.of(context);
  final link = webLink(pin.website);
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        key: const Key('place-sheet'),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 4,
          children: [
            Text(pin.name.isNotEmpty ? pin.name : placeKindText(t, pin.kind, ''), style: theme.textTheme.titleMedium),
            Text(placeKindText(t, pin.kind, pin.detail), style: theme.textTheme.bodyMedium),
            // No launcher plugin in the app: the address to copy.
            if (link != null) SelectableText('${t.placeWebsite}: $link', style: theme.textTheme.bodySmall),
            ...actions,
          ],
        ),
      ),
    ),
  );
}
