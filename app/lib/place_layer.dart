import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:maplibre/maplibre.dart';

import 'api.dart';
import 'format.dart';
import 'l10n/app_localizations.dart';
import 'map_style.dart';
import 'poi_icons.dart';
import 'precip.dart';

/// The places a map can show, each switched on in the layer menu.
enum PlaceGroup { huts, lodging, pois }

const _groupKinds = {
  PlaceGroup.huts: ['hut'],
  PlaceGroup.lodging: ['hotel', 'campsite'],
  PlaceGroup.pois: poiKinds,
};

/// Below these zooms, too many points.
const _groupMinZoom = {PlaceGroup.huts: 8.0, PlaceGroup.lodging: 10.0, PlaceGroup.pois: 12.0};

/// The kinds to fetch for the [shown] groups at [zoom], along the way only
/// the [pois] switched on.
List<String> placeKinds(Set<PlaceGroup> shown, double zoom, [Set<String>? pois]) => [
  for (final g in PlaceGroup.values)
    if (shown.contains(g) && zoom >= _groupMinZoom[g]!)
      for (final k in _groupKinds[g]!)
        if (g != PlaceGroup.pois || pois == null || pois.contains(k)) k,
];

/// The base maps and overlays of swisstopo and the federal offices, as on
/// the website: layer, image type, highest zoom and opacity. The vector
/// base map is left to the website: switching to it would reload the style.
const baseMaps = ['landeskarte', 'landeskarte_grau', 'luftbild'];
const rasterOverlays = ['wanderwege', 'wanderland', 'hangneigung', 'wildruhezonen', 'jagdbanngebiete', 'relief'];
const _raster = {
  'landeskarte_grau': ('ch.swisstopo.pixelkarte-grau', 'jpeg', 19, 1.0),
  'luftbild': ('ch.swisstopo.swissimage', 'jpeg', 20, 1.0),
  'wanderland': ('ch.astra.wanderland', 'png', 18, 1.0),
  'hangneigung': ('ch.swisstopo.hangneigung-ueber_30', 'png', 17, 0.6),
  'wildruhezonen': ('ch.bafu.wrz-wildruhezonen_portal', 'png', 18, 0.7),
  'jagdbanngebiete': ('ch.bafu.bundesinventare-jagdbanngebiete', 'png', 18, 0.6),
  'relief': ('ch.swisstopo.swissalti3d-reliefschattierung', 'png', 18, 0.5),
};

/// What the maps show: off until switched on (the hiking trails on),
/// remembered in the Keychain like the session.
class PlaceSettings {
  PlaceSettings({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  /// Shared by all maps, so a switch holds on the next screen too.
  static final instance = PlaceSettings();

  static const _key = 'map-places';
  final FlutterSecureStorage _storage;
  final shown = ValueNotifier<Set<PlaceGroup>>({});
  final base = ValueNotifier<String>('landeskarte');
  final overlays = ValueNotifier<Set<String>>({'wanderwege'});

  /// The kinds along the way shown when [PlaceGroup.pois] is on.
  final pois = ValueNotifier<Set<String>>({...poiKinds});
  late final Future<void> loaded = _load();

  Future<void> _load() async {
    try {
      final v = await _storage.read(key: _key) ?? '';
      shown.value = {
        for (final name in v.split(','))
          for (final g in PlaceGroup.values)
            if (g.name == name) g,
      };
      final b = await _storage.read(key: '$_key-base');
      if (baseMaps.contains(b)) base.value = b!;
      if (await _storage.read(key: '$_key-overlays') case final o?) {
        overlays.value = o.split(',').where(rasterOverlays.contains).toSet();
      }
      if (await _storage.read(key: '$_key-pois') case final k?) {
        pois.value = k.split(',').where(poiKinds.contains).toSet();
      }
    } on Object {
      // no Keychain (tests): the defaults
    }
  }

  Future<void> toggle(PlaceGroup g) async {
    await loaded;
    shown.value = shown.value.contains(g) ? ({...shown.value}..remove(g)) : {...shown.value, g};
    await _write(_key, shown.value.map((g) => g.name));
  }

  Future<void> setBase(String id) async {
    await loaded;
    base.value = id;
    await _write('$_key-base', [id]);
  }

  Future<void> toggleOverlay(String id) async {
    await loaded;
    overlays.value = overlays.value.contains(id) ? ({...overlays.value}..remove(id)) : {...overlays.value, id};
    await _write('$_key-overlays', overlays.value);
  }

  Future<void> togglePoi(String kind) async {
    await loaded;
    pois.value = pois.value.contains(kind) ? ({...pois.value}..remove(kind)) : {...pois.value, kind};
    await _write('$_key-pois', pois.value);
  }

  Future<void> _write(String key, Iterable<String> values) async {
    try {
      await _storage.write(key: key, value: values.join(','));
    } on Object {
      // not remembered, still switched
    }
  }
}

/// The layers of the layer menu on a MapLibre map: the base map and
/// overlays as raster tiles of [Api.server]'s tile cache, huts (red), hotels
/// (blue) and campsites (green) as dots and what lies along the way as
/// icons, from `GET /places/in-view`. The screen calls [addTo] when its
/// style has loaded, before adding its own layers (which then lie on top),
/// and passes the map's events to [onEvent]. Without a connection what is
/// shown stays.
class PlaceLayer {
  PlaceLayer(this.api, {required this.onTap, PlaceSettings? settings}) : settings = settings ?? PlaceSettings.instance {
    this.settings.shown.addListener(_switched);
    this.settings.pois.addListener(_switched);
    this.settings.base.addListener(_syncRaster);
    this.settings.overlays.addListener(_syncRaster);
  }

  final Api api;
  final void Function(Pin pin) onTap;
  final PlaceSettings settings;

  /// The rain, while the overlay «precip» is on; its bar goes on the screen.
  late final precip = PrecipController(api, settings.overlays);

  static const _id = 'places';
  static const _poisId = 'places-pois';
  static const _alongId = 'places-along';
  static const _markId = 'places-along-mark';
  MapController? _map;
  StyleController? _style;
  Timer? _timer;

  /// Counts the requests: only the latest answer is shown.
  int _asked = 0;
  List<Pin> _shown = const [];

  /// What lies along the screen's route, from [addAlong].
  List<Pin> _along = const [];

  /// Raster layers are added and removed one change after the other.
  Future<void> _rasterDone = Future.value();

  /// The raster layers on the map: the style brings the hiking trails.
  final _rasterShown = <String>{'wanderwege'};

  Future<void> addTo(StyleController style) async {
    _style = null;
    _rasterShown
      ..clear()
      ..add('wanderwege');
    await style.addSource(
      GeoJsonSource(id: _id, data: _geojson(_shownPlaces), attribution: '© OpenStreetMap contributors'),
    );
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
            '#1d4ed8',
          ],
          'circle-stroke-color': '#ffffff',
          'circle-stroke-width': 1.5,
        },
      ),
    );
    // Drawn three times as large: images are taken at one pixel a point.
    for (final kind in poiKinds) {
      await style.addImageFromCanvas(
        id: 'poi-$kind',
        width: 66,
        height: 66,
        painter: (canvas) => paintPoiIcon(canvas, kind, 66),
      );
    }
    // Their own source, not a filter on one: MapLibre's iOS plugin turns
    // filters into predicates, which drop expressions like «in».
    await style.addSource(
      GeoJsonSource(id: _poisId, data: _geojson(_shownPois), attribution: '© OpenStreetMap contributors'),
    );
    await style.addLayer(
      const SymbolStyleLayer(
        id: _poisId,
        sourceId: _poisId,
        layout: {
          'icon-image': ['get', 'icon'],
          'icon-size': [
            'interpolate',
            ['linear'],
            ['zoom'],
            12,
            0.28,
            16,
            0.36,
          ],
          'icon-allow-overlap': false,
        },
      ),
    );
    _style = style;
    await settings.loaded;
    _syncRaster();
    precip.attach(style, below: _id);
    _load(now: true);
  }

  /// What lies along a route, drawn with the kinds' icons on top of the
  /// screen's layers (call after [addTo] and the route line); the kinds
  /// switched off in the layer menu stay off.
  Future<void> addAlong(StyleController style, List<Poi> pois) async {
    _along = [for (final (i, p) in pois.indexed) p.toPin(i)];
    // Under the icons: a ring around the points of the line tapped in the list.
    await style.addSource(GeoJsonSource(id: _markId, data: _geojson(const [])));
    await style.addLayer(
      const CircleStyleLayer(
        id: _markId,
        sourceId: _markId,
        paint: {
          'circle-radius': 16,
          'circle-color': '#f28a48',
          'circle-opacity': 0.35,
          'circle-stroke-color': '#f28a48',
          'circle-stroke-width': 2,
        },
      ),
    );
    await style.addSource(GeoJsonSource(id: _alongId, data: _alongJson(), attribution: '© OpenStreetMap contributors'));
    await style.addLayer(
      const SymbolStyleLayer(
        id: _alongId,
        sourceId: _alongId,
        layout: {
          'icon-image': ['get', 'icon'],
          'icon-size': [
            'interpolate',
            ['linear'],
            ['zoom'],
            10,
            0.24,
            16,
            0.36,
          ],
          'icon-allow-overlap': true, // few, along one line
        },
      ),
    );
  }

  /// Rings [points] (a line of the list along the route) and moves the map
  /// to the first of them.
  Future<void> markAlong(List<Poi> points) async {
    await _style
        ?.updateGeoJsonSource(id: _markId, data: _geojson([for (final (i, p) in points.indexed) p.toPin(i)]))
        .catchError((_) {});
    if (points.firstOrNull case final p?) {
      await _map
          ?.animateCamera(
            center: Geographic(lon: p.lon, lat: p.lat),
            nativeDuration: const Duration(milliseconds: 400),
          )
          .catchError((_) {});
    }
  }

  String _alongJson() => _geojson(_along.where((p) => settings.pois.value.contains(p.kind)).toList());

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
    settings.pois.removeListener(_switched);
    settings.base.removeListener(_syncRaster);
    settings.overlays.removeListener(_syncRaster);
    precip.dispose();
    _timer?.cancel();
    _asked++;
    _style = null;
  }

  /// Switched off: gone at once; switched on: fetched.
  void _switched() {
    final kinds = placeKinds(settings.shown.value, double.infinity, settings.pois.value).toSet();
    _show(_shown.where((p) => kinds.contains(p.kind)).toList());
    if (_along.isNotEmpty) _style?.updateGeoJsonSource(id: _alongId, data: _alongJson()).catchError((_) {});
    _load(now: true);
  }

  /// The base map above the style's national map, the overlays above it in
  /// the menu's order, all below the places. The style's hiking trails are
  /// the overlay «wanderwege».
  void _syncRaster() {
    _rasterDone = _rasterDone.then((_) async {
      final style = _style;
      if (style == null) return;
      try {
        final base = settings.base.value;
        final wanted = [
          if (base != 'landeskarte') 'base-$base',
          for (final o in rasterOverlays)
            if (settings.overlays.value.contains(o)) o == 'wanderwege' ? o : 'ovl-$o',
        ];
        for (final id in [..._rasterShown]) {
          if (wanted.contains(id)) continue;
          await style.removeLayer(id);
          if (id != 'wanderwege') await style.removeSource(id);
          _rasterShown.remove(id);
        }
        for (final (i, id) in wanted.indexed.toList().reversed) {
          if (_rasterShown.contains(id)) continue;
          // Below the next one shown, else below the places.
          final below = wanted.skip(i + 1).where(_rasterShown.contains).firstOrNull ?? _id;
          final (layer, ext, maxzoom, opacity) =
              _raster[id.replaceFirst(RegExp('^(base|ovl)-'), '')] ?? ('', '', 0, 1.0);
          if (id != 'wanderwege') {
            await style.addSource(
              RasterSource(
                id: id,
                tiles: ['${api.server}/tiles/wmts/$layer/{z}/{x}/{y}.$ext'],
                tileSize: 256,
                maxZoom: maxzoom.toDouble(),
                bounds: chBounds,
                attribution: '© swisstopo',
              ),
            );
          }
          await style.addLayer(
            RasterStyleLayer(id: id, sourceId: id, paint: {'raster-opacity': opacity}),
            belowLayerId: below,
          );
          _rasterShown.add(id);
        }
      } on Object {
        // the map went away meanwhile
      }
    });
  }

  /// Once the map rests a moment.
  void _load({bool now = false}) {
    _timer?.cancel();
    _timer = Timer(now ? Duration.zero : const Duration(milliseconds: 300), () async {
      final map = _map;
      if (map == null || _style == null) return;
      final asked = ++_asked;
      final kinds = placeKinds(settings.shown.value, map.getCamera().zoom, settings.pois.value);
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

  /// Huts and accommodation as dots, what lies along the way as icons.
  List<Pin> get _shownPlaces => [
    for (final p in _shown)
      if (!poiIcons.containsKey(p.kind)) p,
  ];
  List<Pin> get _shownPois => [
    for (final p in _shown)
      if (poiIcons.containsKey(p.kind)) p,
  ];

  void _show(List<Pin> pins) {
    _shown = pins;
    _style?.updateGeoJsonSource(id: _id, data: _geojson(_shownPlaces)).catchError((_) {});
    _style?.updateGeoJsonSource(id: _poisId, data: _geojson(_shownPois)).catchError((_) {});
  }

  /// A finger is wider than a dot.
  void _tap(Offset at) {
    final map = _map;
    if (map == null || _style == null || (_shown.isEmpty && _along.isEmpty)) return;
    final found = map.featuresInRect(
      Rect.fromCircle(center: at, radius: 16),
      layerIds: [_id, _poisId, if (_along.isNotEmpty) _alongId],
    );
    if (found.isEmpty) return;
    final id = found.first.properties['id'];
    if ([..._shown, ..._along].where((p) => p.id == id).firstOrNull case final pin?) onTap(pin);
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
          // The icon's image by name: a plain property, as iOS takes it.
          'properties': {'id': p.id, 'kind': p.kind, 'icon': 'poi-${p.kind}'},
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
          isScrollControlled: true,
          builder: (context) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            builder: (context, scroll) => SafeArea(
              child: ListenableBuilder(
                listenable: Listenable.merge([s.shown, s.base, s.overlays, s.pois]),
                builder: (context, _) => ListView(
                  controller: scroll,
                  children: [
                    ListTile(title: Text(t.mapBase, style: Theme.of(context).textTheme.titleSmall)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SegmentedButton<String>(
                        key: const Key('map-base'),
                        showSelectedIcon: false,
                        segments: [for (final b in baseMaps) ButtonSegment(value: b, label: Text(baseMapText(t, b)))],
                        selected: {s.base.value},
                        onSelectionChanged: (v) => s.setBase(v.first),
                      ),
                    ),
                    ListTile(title: Text(t.mapOverlays, style: Theme.of(context).textTheme.titleSmall)),
                    for (final o in rasterOverlays)
                      SwitchListTile(
                        key: Key('map-overlay-$o'),
                        title: Text(overlayText(t, o)),
                        value: s.overlays.value.contains(o),
                        onChanged: (_) => s.toggleOverlay(o),
                      ),
                    SwitchListTile(
                      key: const Key('map-overlay-precip'),
                      title: Text(t.mapOverlayPrecip),
                      value: s.overlays.value.contains('precip'),
                      onChanged: (_) => s.toggleOverlay('precip'),
                    ),
                    for (final (g, label) in [
                      (PlaceGroup.huts, t.mapHuts),
                      (PlaceGroup.lodging, t.mapLodging),
                      (PlaceGroup.pois, t.mapPois),
                    ])
                      SwitchListTile(
                        key: Key('map-layer-${g.name}'),
                        title: Text(label),
                        value: s.shown.value.contains(g),
                        onChanged: (_) => s.toggle(g),
                      ),
                    if (s.shown.value.contains(PlaceGroup.pois))
                      for (final k in poiKinds)
                        CheckboxListTile(
                          key: Key('map-poi-$k'),
                          dense: true,
                          contentPadding: const EdgeInsets.only(left: 32, right: 16),
                          secondary: PoiIcon(k, size: 22),
                          title: Text(placeKindText(t, k, '')),
                          value: s.pois.value.contains(k),
                          onChanged: (_) => s.togglePoi(k),
                        ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      child: const Icon(Icons.layers_outlined),
    );
  }
}

String baseMapText(AppLocalizations t, String id) => switch (id) {
  'landeskarte_grau' => t.mapBaseGrey,
  'luftbild' => t.mapBaseAerial,
  _ => t.mapBaseNational,
};

String overlayText(AppLocalizations t, String id) => switch (id) {
  'wanderwege' => t.mapOverlayTrails,
  'wanderland' => t.mapOverlayWanderland,
  'hangneigung' => t.mapOverlaySlope,
  'wildruhezonen' => t.mapOverlayRestAreas,
  'jagdbanngebiete' => t.mapOverlayHuntingReserves,
  _ => t.mapOverlayRelief,
};

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
  'firepit' => t.poiFirepit,
  'picnic' => t.poiPicnic,
  'restaurant' => t.poiRestaurant,
  'toilets' => t.poiToilets,
  'cablecar' => t.poiCablecar,
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
            if (link != null) SelectableText(t.labelled(t.placeWebsite, link), style: theme.textTheme.bodySmall),
            ...actions,
          ],
        ),
      ),
    ),
  );
}
