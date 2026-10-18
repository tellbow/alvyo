# maplibre_android implements Flutter's PlatformView in Dart through JNI and
# matches the calls by their descriptor, e.g.
# createPlatformView(I)Lio/flutter/plugin/platform/PlatformView;. Renamed by
# R8, nothing matches and release builds show no map (feedback issues 10, 18).
-keep interface io.flutter.plugin.platform.PlatformView { *; }
