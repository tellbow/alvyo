import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Warnings that reach the hiker with the phone in the pocket: a local
/// notification vibrates also while the app is in the background.
class Alerts {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _init;
  bool _ready = false;

  /// Asks for permission the first time; completes once answered.
  Future<void> init() => _init ??= () async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(requestBadgePermission: false),
        android: AndroidInitializationSettings('ic_notification'),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _ready = true;
  }();

  /// On Android, [title] also names the notifications in the system settings.
  Future<void> offRoute(String title, String body) async {
    await init();
    await _plugin.show(
      id: 1,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        iOS: const DarwinNotificationDetails(presentSound: true),
        android: AndroidNotificationDetails('off-route', title, importance: Importance.high, priority: Priority.high),
      ),
    );
  }

  /// Removes the warning; never waits for the permission question.
  Future<void> clear() async {
    if (_ready) await _plugin.cancel(id: 1);
  }
}
