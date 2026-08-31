import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

class NativeNotifications {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static final _details = NotificationDetails(
    android: const AndroidNotificationDetails(
      'nareru_reminders', 'Habit reminders',
      channelDescription: 'Reminders for habits you scheduled in Nareru',
      importance: Importance.high, priority: Priority.high,
    ),
    iOS: const DarwinNotificationDetails(),
    macOS: const DarwinNotificationDetails(),
    linux: const LinuxNotificationDetails(urgency: LinuxNotificationUrgency.normal),
    windows: WindowsNotificationDetails(),
  );

  static Future<void> initialize({bool requestPermissions = false}) async {
    if (!_initialized) {
      tz_data.initializeTimeZones();
      final settings = InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: const DarwinInitializationSettings(),
        macOS: const DarwinInitializationSettings(),
        linux: const LinuxInitializationSettings(defaultActionName: 'Open Nareru'),
        windows: WindowsInitializationSettings(
          appName: 'Nareru', appUserModelId: 'com.roroca.nareru',
          guid: '9256a6ec-a670-4c38-a7ed-59da92f684a7',
        ),
      );
      await _plugin.initialize(settings: settings);
      _initialized = true;
    }
    if (requestPermissions) await _requestPermissions();
  }

  static Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isMacOS) {
      await _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  static Future<void> test() async {
    await initialize(requestPermissions: true);
    await _plugin.show(
      id: 991001, title: 'Nareru test',
      body: 'Notifications are working on this device.',
      notificationDetails: _details,
    );
  }

  static Future<void> reschedule(List<Habit> habits) async {
    await initialize(requestPermissions: true);
    if (Platform.isLinux) return;
    await _plugin.cancelAll();
    final now = DateTime.now();
    var id = 1000;
    for (var offset = 0; offset < 30 && id < 1060; offset++) {
      final date = day(now.add(Duration(days: offset)));
      for (final habit in habits) {
        if (!habit.schedule.isDue(date) || habit.reminder.mode == ReminderMode.none) continue;
        for (final minutes in _times(habit.reminder)) {
          final when = date.add(Duration(minutes: minutes));
          if (!when.isAfter(now) || id >= 1060) continue;
          await _plugin.zonedSchedule(
            id++, title: '${habit.emoji} ${habit.name}',
            body: 'Time for your habit • goal ${habit.goal} ${habit.unit}',
            scheduledDate: tz.TZDateTime.from(when.toUtc(), tz.UTC),
            notificationDetails: _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      }
    }
  }

  static Iterable<int> _times(Reminder reminder) sync* {
    if (reminder.mode == ReminderMode.fixedTime) {
      yield reminder.time!.hour * 60 + reminder.time!.minute;
    } else if (reminder.mode == ReminderMode.interval) {
      final start = reminder.start!.hour * 60 + reminder.start!.minute;
      final end = reminder.end!.hour * 60 + reminder.end!.minute;
      final limit = end >= start ? end : end + 1440;
      for (var value = start; value <= limit; value += reminder.minutes!) yield value;
    }
  }
}
