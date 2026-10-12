import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'api.dart';
import 'l10n/app_localizations.dart';

/// A reminder on the phone before a journey starts.
typedef PhoneReminder = ({int id, String kind, DateTime at});

/// The reminders still to come for a journey starting on [start] (Swiss
/// local time): three weeks before at 9 to book the nights (only while some
/// are not booked), two days and one day before at 18 for the weather and
/// the start. [journeyId] gives each its own notification id.
List<PhoneReminder> journeyReminders(
  String journeyId,
  DateTime start, {
  required bool unbooked,
  required DateTime now,
}) {
  // A hash that stays the same between runs (FNV-1a): the ids replace the
  // ones scheduled before.
  var h = 0x811c9dc5;
  for (final c in journeyId.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  final base = h % 100000000 * 10;
  return [
    if (unbooked) (id: base + 1, kind: 'book', at: DateTime(start.year, start.month, start.day - 21, 9)),
    (id: base + 2, kind: 'weather', at: DateTime(start.year, start.month, start.day - 2, 18)),
    (id: base + 3, kind: 'start', at: DateTime(start.year, start.month, start.day - 1, 18)),
  ].where((r) => r.at.isAfter(now)).toList();
}

/// Whether nights before the last stage are not booked yet.
bool hasUnbooked(JourneyDetail j) => [
  for (final (i, s) in j.stages.indexed)
    if (i < j.stages.length - 1 && s.status == 'planned' && !s.booked) s,
].isNotEmpty;

/// Schedules a journey's reminders as local notifications, replacing those
/// scheduled before; with [on] false only removes them.
class PhoneReminders {
  PhoneReminders._();
  static final instance = PhoneReminders._();

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _init;

  // Without asking: opening a journey removes its old reminders, which
  // needs no permission. It is asked when reminders are scheduled.
  Future<void> _ready() => _init ??= () async {
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
        android: AndroidInitializationSettings('ic_notification'),
      ),
    );
  }();

  Future<void> schedule(AppLocalizations t, JourneyDetail j, {required bool on, required DateTime? start}) async {
    try {
      await _ready();
      final zurich = tz.getLocation('Europe/Zurich');
      // The ids depend on the journey only: all three go, whatever the start was.
      for (final r in journeyReminders(j.id, DateTime(3000), unbooked: true, now: DateTime(0))) {
        await _plugin.cancel(id: r.id);
      }
      if (!on || start == null) return;
      final due = journeyReminders(j.id, start, unbooked: hasUnbooked(j), now: DateTime.now());
      if (due.isEmpty) return;
      await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
        alert: true,
        sound: true,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      for (final r in due) {
        await _plugin.zonedSchedule(
          id: r.id,
          title: j.title,
          body: switch (r.kind) {
            'book' => t.reminderBook,
            'weather' => t.reminderWeather,
            _ => t.reminderStart,
          },
          scheduledDate: tz.TZDateTime(zurich, r.at.year, r.at.month, r.at.day, r.at.hour),
          notificationDetails: NotificationDetails(
            iOS: const DarwinNotificationDetails(),
            android: AndroidNotificationDetails('reminders', t.channelReminders),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } on Object {
      // no notifications (tests, permission refused): the e-mails remain
    }
  }
}
