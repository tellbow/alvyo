import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre/maplibre.dart';

import 'l10n/app_localizations.dart';
import 'navigation/gps.dart';

/// Shows the phone's position on [map], if the app may already use the
/// location; never asks. MapLibre's own dot, not the GPS of a hike:
/// geolocator has one stream for the whole app, and the first listener's
/// settings would hold for the hike too. Call it once the style is loaded
/// (Android draws the dot into it).
Future<void> showMyLocation(MapController? map) async {
  if (map == null || await locationAccess() != LocationAccess.allowed) return;
  try {
    await map.enableLocation();
  } on Object {
    // the map is gone
  }
}

/// «Mein Standort» as in Apple's and Google's maps: moves the map to the
/// phone's position; asks for the location first, or opens the settings
/// where only they can help.
class MyLocationButton extends StatefulWidget {
  const MyLocationButton({super.key, required this.map});

  /// The map, once created.
  final MapController? Function() map;

  @override
  State<MyLocationButton> createState() => _MyLocationButtonState();
}

class _MyLocationButtonState extends State<MyLocationButton> {
  bool _finding = false;

  Future<void> _locate() async {
    setState(() => _finding = true);
    final ({double lon, double lat})? at;
    try {
      if (!await _allowed()) return;
      await showMyLocation(widget.map());
      at = await knownPosition(maxAge: const Duration(minutes: 1));
    } on Object {
      return; // a question already open
    } finally {
      if (mounted) setState(() => _finding = false);
    }
    if (!mounted) return;
    final map = widget.map();
    if (at == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).discoverNearbyUnknown)));
      return;
    }
    if (map == null) return;
    try {
      await map.animateCamera(
        center: Geographic(lon: at.lon, lat: at.lat),
        zoom: max(map.getCamera().zoom, 15),
        nativeDuration: const Duration(milliseconds: 600),
      );
    } on Object {
      // cut short by a gesture
    }
  }

  /// Whether the location may be used now; asks, or opens the settings.
  Future<bool> _allowed() async {
    switch (await locationAccess()) {
      case LocationAccess.off:
        await Geolocator.openLocationSettings();
        return false;
      case LocationAccess.settings:
        await Geolocator.openAppSettings();
        return false;
      case LocationAccess.ask:
        final p = await Geolocator.requestPermission();
        return p == LocationPermission.whileInUse || p == LocationPermission.always;
      case LocationAccess.allowed:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) => FloatingActionButton.small(
    key: const Key('map-my-location'),
    heroTag: null, // several on a stack of screens
    tooltip: AppLocalizations.of(context).mapMyLocation,
    onPressed: _finding ? null : _locate,
    child: _finding
        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.my_location),
  );
}
