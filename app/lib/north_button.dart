import 'package:material_ui/material_ui.dart';
import 'package:maplibre/maplibre.dart';

import 'l10n/app_localizations.dart';

/// Turns a rotated map back to north (feedback issue 92); the needle shows
/// where north is. Only while the map is rotated, and only in
/// [MapLibreMap.children]: there it rebuilds with every camera move. The
/// maps' own compasses are off on both platforms.
class NorthButton extends StatelessWidget {
  const NorthButton({super.key});

  @override
  Widget build(BuildContext context) {
    final bearing = MapCamera.maybeOf(context)?.bearing ?? 0;
    // Within half a degree it is north: pinching turns the map a little.
    if (bearing.abs() < 0.5 || (360 - bearing).abs() < 0.5) return const SizedBox.shrink();
    return FloatingActionButton.small(
      key: const Key('map-north'),
      heroTag: null, // several on a stack of screens
      tooltip: AppLocalizations.of(context).mapNorth,
      onPressed: () => MapController.maybeOf(
        context,
      )?.animateCamera(bearing: 0, nativeDuration: const Duration(milliseconds: 300)).catchError((_) {}),
      child: Transform.rotate(angle: -bearing * degree2Radian, child: const Icon(Icons.navigation)),
    );
  }
}
