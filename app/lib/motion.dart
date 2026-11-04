import 'package:flutter/widgets.dart';

/// Whether the phone asks for less motion: Android's «Remove animations», or
/// iOS's «Reduce Motion», which Flutter reports separately.
bool lessMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ||
    WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.reduceMotion;
