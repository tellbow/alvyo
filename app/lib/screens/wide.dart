import 'package:flutter/material.dart';

/// An iPad, or a phone turned sideways (requirement 73): the tabs in a rail
/// on the left, a map's panel beside it instead of under it, lists no wider
/// than they read well. 820 is an iPad's narrowest full screen upright
/// (the mini's 744 keeps the phone's layout, as Split View does).
bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 820;

/// The width of a map's panel on a wide screen: a phone's, which its content fits.
const panelWidth = 375.0;

/// A map with its panel: under it on a phone ([share] of the height, or
/// [height]; without either the panel alone), on its left on a wide
/// screen. The map stays the first child either way, so turning the phone
/// does not build it anew.
class MapSplit extends StatelessWidget {
  const MapSplit({super.key, required this.map, required this.panel, this.share, this.height})
    : assert(share == null || height == null);
  final Widget map;
  final Widget panel;
  final double? share;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    if (!wide && share == null && height == null) return panel;
    return LayoutBuilder(
      builder: (context, size) => Flex(
        direction: wide ? Axis.horizontal : Axis.vertical,
        // Right to left: the panel, the last child, comes first on the left.
        textDirection: TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: map),
          if (wide) const VerticalDivider(width: 1),
          SizedBox(
            key: const Key('map-panel'),
            width: wide ? panelWidth : null,
            height: wide ? null : height ?? size.maxHeight * share!,
            child: panel,
          ),
        ],
      ),
    );
  }
}

/// A list or form no wider than it reads well, in the middle of a wide
/// screen; as wide as the screen when not [on] (a map instead).
class Readable extends StatelessWidget {
  const Readable({super.key, required this.child, this.on = true});
  final Widget child;
  final bool on;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: on ? 720 : double.infinity),
      child: child,
    ),
  );
}
