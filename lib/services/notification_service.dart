import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:planetxt/constants/app_constants.dart';
import 'package:planetxt/services/in_app_reminder_scheduler.dart';
import 'package:planetxt/services/shared_prefs_service.dart';
import 'package:planetxt/services/storage_service.dart';
import 'package:planetxt/utils/daily_file_naming.dart';
import 'package:planetxt/utils/logger.dart';
import 'package:planetxt/utils/markdown_parser.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const int defaultReminderMinutes = 60;

  /// The day of the reminder the user tapped (`yyyyMMdd`): the app shows
  /// it. Reset to null once handled.
  final ValueNotifier<String?> openDayRequest = ValueNotifier(null);

  /// Minutes before an event its reminder fires; null: reminders are off.
  int? get reminderMinutes {
    try {
      final minutes =
          SharedPrefsService.instance.getInt(AppConstants.reminderMinutesKey);
      if (minutes == null) return defaultReminderMinutes;
      return minutes < 0 ? null : minutes;
    } on StateError {
      return defaultReminderMinutes; // preferences not loaded (tests)
    }
  }

  /// Set [reminderMinutes] and drop the reminders scheduled with the old
  /// delay; the caller schedules them again.
  Future<void> setReminderMinutes(int? minutes) async {
    await SharedPrefsService.instance
        .setInt(AppConstants.reminderMinutesKey, minutes ?? -1);
    await cancelAllNotifications();
  }

  /// When the reminder of an event at [eventTime] fires, [minutesBefore]
  /// ahead; null when reminders are off or that time has passed.
  static DateTime? reminderTime(
      DateTime eventTime, int? minutesBefore, DateTime now) {
    if (minutesBefore == null) return null;
    final fireAt = eventTime.subtract(Duration(minutes: minutesBefore));
    return fireAt.isBefore(now) ? null : fireAt;
  }

  /// The day a reminder's payload (`event_<yyyyMMdd>_<id>`) points to.
  @visibleForTesting
  static String? dateFromPayload(String? payload) =>
      RegExp(r'^event_(\d{8})_').firstMatch(payload ?? '')?.group(1);

  void _openDayOf(String? payload) {
    final date = dateFromPayload(payload);
    if (date != null) openDayRequest.value = date;
  }

  /// The Linux plugin cannot schedule notifications: there, reminders are
  /// fired by the app itself, while it runs.
  late final InAppReminderScheduler? _inAppReminders = Platform.isLinux
      ? InAppReminderScheduler(onFire: _showInAppReminder)
      : null;

  void _showInAppReminder(InAppReminder reminder) {
    unawaited(_notifications
        .show(
          id: reminder.id,
          title: reminder.title,
          body: reminder.body,
          notificationDetails: _notificationDetails,
          payload: reminder.payload,
        )
        .catchError((Object e) =>
            Log.e('NotificationService: could not show reminder', error: e)));
  }

  /// Scheduled reminders, wherever they wait.
  Future<List<PendingNotificationRequest>> _pendingRequests() async {
    final inApp = _inAppReminders;
    if (inApp == null) return _notifications.pendingNotificationRequests();
    return [
      for (final r in inApp.pending)
        PendingNotificationRequest(r.id, r.title, r.body, r.payload),
    ];
  }

  static const String _channelId = 'event_reminders';
  static const String _channelName = 'Event Reminders';
  static const String _channelDesc =
      'Notifications for upcoming events in PlaneTxt';

  NotificationDetails get _notificationDetails => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max,
          priority: Priority.max,
          showWhen: true,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
          category: AndroidNotificationCategory.reminder,
          visibility: NotificationVisibility.public,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        linux: LinuxNotificationDetails(
          urgency: LinuxNotificationUrgency.normal,
          defaultActionName: 'Open notification',
        ),
      );

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    try {
      final timeZoneInfo = await FlutterTimezone.getLocalTimezone();
      final timeZoneName = timeZoneInfo.identifier;
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      Log.i('NotificationService: timezone=$timeZoneName');
    } catch (e) {
      Log.e('NotificationService: Failed to get timezone', error: e);
    }

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
      linux: LinuxInitializationSettings(
        defaultActionName: 'Open notification',
      ),
    );

    await _notifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        Log.i('Notification tapped: ${response.payload}');
        _openDayOf(response.payload);
      },
    );

    _initialized = true;

    // Started by a tap on a reminder: open on its day.
    try {
      final launch = await _notifications.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _openDayOf(launch!.notificationResponse?.payload);
      }
    } catch (e) {
      Log.w('NotificationService: no launch details', error: e);
    }

    if (Platform.isAndroid) {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
            enableLights: true,
          ),
        );

        final enabled = await androidPlugin.areNotificationsEnabled();
        final canExact = await androidPlugin.canScheduleExactNotifications();
        Log.i(
            'NotificationService: notificationsEnabled=$enabled, canScheduleExact=$canExact');
      }
    }
  }

  /// Ask for the notification permission on the first launch only: after
  /// that, the system settings decide, rather than a prompt at every start.
  Future<void> requestPermissionsOnce() async {
    final prefs = SharedPrefsService.instance;
    if (prefs.getBool(AppConstants.notificationPermissionAskedKey) ?? false) {
      return;
    }
    await prefs.setBool(AppConstants.notificationPermissionAskedKey, true);
    await requestPermissions();
  }

  /// Reminders are scheduled as inexact alarms, so the exact-alarm access
  /// is not asked for here (it opened the system settings at every start);
  /// the home screen widget asks for it from Widget Health.
  Future<bool> requestPermissions() async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return true;
    }

    try {
      final status = await Permission.notification.request();
      Log.i('NotificationService: POST_NOTIFICATIONS=$status');
      return status.isGranted;
    } catch (e) {
      Log.e('NotificationService: permission request failed', error: e);
      return false;
    }
  }

  /// Fire an immediate notification right now. Use this to test if the
  /// notification channel and permissions work at all.
  Future<void> showTestNotification() async {
    if (!_initialized) await initialize();

    Log.i('NotificationService: Firing immediate test notification');
    await _notifications.show(
      id: 0,
      title: 'PlaneTxt Test',
      body: 'If you see this, notifications work!',
      notificationDetails: _notificationDetails,
      payload: 'test',
    );
    Log.i('NotificationService: show() completed');
  }

  /// Schedule a test notification 15 seconds from now using zonedSchedule.
  /// Tests all three modes so we can identify which AlarmManager API works.
  Future<void> showScheduledTestNotification() async {
    if (!_initialized) await initialize();

    final now = tz.TZDateTime.now(tz.local);

    // Test 1: alarmClock mode (setAlarmClock - most reliable, at 15s)
    final time1 = now.add(const Duration(seconds: 15));
    Log.i('NotificationService: TEST alarmClock at $time1');
    try {
      await _notifications.zonedSchedule(
        id: 1,
        title: 'Test: alarmClock mode',
        body: 'This used setAlarmClock()',
        scheduledDate: time1,
        notificationDetails: _notificationDetails,
        payload: 'test_alarmClock',
        androidScheduleMode: AndroidScheduleMode.alarmClock,
      );
      Log.i('NotificationService: alarmClock scheduled OK');
    } catch (e) {
      Log.e('NotificationService: alarmClock FAILED', error: e);
    }

    // Test 2: exactAllowWhileIdle mode (setExactAndAllowWhileIdle, at 30s)
    final time2 = now.add(const Duration(seconds: 30));
    Log.i('NotificationService: TEST exactAllowWhileIdle at $time2');
    try {
      await _notifications.zonedSchedule(
        id: 2,
        title: 'Test: exactAllowWhileIdle mode',
        body: 'This used setExactAndAllowWhileIdle()',
        scheduledDate: time2,
        notificationDetails: _notificationDetails,
        payload: 'test_exact',
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      Log.i('NotificationService: exactAllowWhileIdle scheduled OK');
    } catch (e) {
      Log.e('NotificationService: exactAllowWhileIdle FAILED', error: e);
    }

    // Test 3: inexactAllowWhileIdle mode (setAndAllowWhileIdle, at 45s)
    final time3 = now.add(const Duration(seconds: 45));
    Log.i('NotificationService: TEST inexactAllowWhileIdle at $time3');
    try {
      await _notifications.zonedSchedule(
        id: 3,
        title: 'Test: inexactAllowWhileIdle mode',
        body: 'This used setAndAllowWhileIdle()',
        scheduledDate: time3,
        notificationDetails: _notificationDetails,
        payload: 'test_inexact',
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      Log.i('NotificationService: inexactAllowWhileIdle scheduled OK');
    } catch (e) {
      Log.e('NotificationService: inexactAllowWhileIdle FAILED', error: e);
    }

    // Verify all are pending
    final pending = await _pendingRequests();
    Log.i(
        'NotificationService: ${pending.length} pending after scheduling tests');
    for (final n in pending) {
      Log.i('  pending: id=${n.id}');
    }
  }

  /// Fire a notification after a delay using a Dart Timer (bypasses AlarmManager).
  /// If this works but zonedSchedule doesn't, AlarmManager is broken.
  Future<void> showTimerTestNotification() async {
    if (!_initialized) await initialize();

    Log.i('NotificationService: Will fire notification via Dart Timer in 10s');
    Future.delayed(const Duration(seconds: 10), () async {
      Log.i('NotificationService: Timer fired, showing notification now');
      await _notifications.show(
        id: 99,
        title: 'PlaneTxt Timer Test',
        body: 'This bypassed AlarmManager entirely (Dart Timer + show())',
        notificationDetails: _notificationDetails,
        payload: 'test_timer',
      );
      Log.i('NotificationService: Timer notification shown');
    });
  }

  Future<AndroidScheduleMode> _getBestScheduleMode() async {
    if (!Platform.isAndroid) {
      return AndroidScheduleMode.alarmClock;
    }

    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  Future<void> scheduleEventNotification({
    required int id,
    required String title,
    required String description,
    required DateTime eventDateTime,
    required String date,
  }) async {
    if (!_initialized) await initialize();

    final notificationTime =
        reminderTime(eventDateTime, reminderMinutes, DateTime.now());
    if (notificationTime == null) {
      Log.d('NotificationService: no reminder for "$title" (off or past)');
      return;
    }

    final eventHour = eventDateTime.hour.toString().padLeft(2, '0');
    final eventMinute = eventDateTime.minute.toString().padLeft(2, '0');
    final timeStr = '$eventHour:$eventMinute';

    final inApp = _inAppReminders;
    if (inApp != null) {
      inApp.schedule(InAppReminder(
        id: id,
        fireAt: notificationTime,
        eventTime: eventDateTime,
        title: '$timeStr - $title',
        body: description,
        payload: 'event_${date}_$id',
      ));
      Log.i('NotificationService: in-app reminder id=$id at '
          '$notificationTime');
      return;
    }

    final scheduledTZ = tz.TZDateTime.from(notificationTime, tz.local);
    final mode = await _getBestScheduleMode();

    try {
      await _notifications.zonedSchedule(
        id: id,
        title: '$timeStr - $title',
        body: description,
        scheduledDate: scheduledTZ,
        notificationDetails: _notificationDetails,
        payload: 'event_${date}_$id',
        androidScheduleMode: mode,
      );

      // Verify the notification is actually pending
      final pending = await _pendingRequests();
      final found = pending.any((n) => n.id == id);

      Log.i(
          'NotificationService: scheduled id=$id at $scheduledTZ mode=$mode verified=$found');
    } catch (e) {
      Log.e('NotificationService: FAILED to schedule id=$id', error: e);
      // Try inexact as last resort
      if (mode != AndroidScheduleMode.inexactAllowWhileIdle) {
        try {
          await _notifications.zonedSchedule(
            id: id,
            title: '$timeStr - $title',
            body: description,
            scheduledDate: scheduledTZ,
            notificationDetails: _notificationDetails,
            payload: 'event_${date}_$id',
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
          Log.i('NotificationService: scheduled id=$id with inexact fallback');
        } catch (e2) {
          Log.e('NotificationService: inexact fallback also failed', error: e2);
        }
      }
    }
  }

  Future<void> cancelNotification(int id) async {
    _inAppReminders?.cancel(id);
    await _notifications.cancel(id: id);
  }

  Future<void> cancelAllNotifications() async {
    _inAppReminders?.cancelAll();
    await _notifications.cancelAll();
  }

  Future<List<PendingNotificationRequest>> getPendingNotifications() =>
      _pendingRequests();

  Future<void> cancelNotificationsForDate(String date) async {
    final pending = await _pendingRequests();
    for (final n in pending) {
      final payload = n.payload ?? '';
      if (payload.startsWith('event_${date}_')) {
        await cancelNotification(n.id);
      }
    }
  }

  static int generateEventId(String eventTitle, DateTime eventDateTime) {
    final combined = '${eventTitle}_${eventDateTime.millisecondsSinceEpoch}';
    return combined.hashCode & 0x7FFFFFFF;
  }

  /// Get a diagnostic string with current notification system status
  Future<String> getDiagnostics() async {
    if (!_initialized) await initialize();

    final lines = <String>[];

    lines.add('Initialized: $_initialized');
    lines.add('Timezone: ${tz.local.name}');
    lines.add('Now: ${tz.TZDateTime.now(tz.local)}');

    if (Platform.isAndroid) {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final enabled = await androidPlugin.areNotificationsEnabled();
        final canExact = await androidPlugin.canScheduleExactNotifications();
        lines.add('Notifications enabled: $enabled');
        lines.add('Can schedule exact: $canExact');
      }
    }

    final pending = await _pendingRequests();
    lines.add('Pending notifications: ${pending.length}');
    for (final n in pending) {
      lines.add('  id=${n.id} title="${n.title}" payload=${n.payload}');
    }

    return lines.join('\n');
  }

  /// Pass [contentByDate] (date -> daily file content) when the caller
  /// already has the files in memory; otherwise the dailies directory is
  /// read in one bulk pass. Never read files one by one here - on SAF each
  /// individual read re-scans its parent directory.
  Future<void> reviewNotifications({
    Map<String, String>? contentByDate,
  }) async {
    if (!_initialized) await initialize();

    try {
      final pending = await _pendingRequests();
      if (pending.isEmpty) return;

      Log.d(
          'NotificationService: reviewing ${pending.length} pending notifications');

      final validEventsByDate = <String, Set<int>>{};

      void addValidEvents(String date, String content) {
        try {
          final events = MarkdownParser.parseEvents(date, content);
          validEventsByDate[date] = events
              .map((e) => generateEventId(e.displayTitle, e.time))
              .toSet();
        } catch (e) {
          Log.e('NotificationService: error parsing daily $date', error: e);
        }
      }

      if (contentByDate != null) {
        contentByDate.forEach(addValidEvents);
      } else {
        final store = StorageService().store;
        if (store != null) {
          final entries = await store.list(StorageService.dailiesDirName);
          final dateByPath = <String, String>{};
          for (final entry in entries) {
            final date = DailyFileNaming.current.dateOf(entry.relPath);
            if (date != null) dateByPath[entry.relPath] = date;
          }
          final contents = await store.readAll(dateByPath.keys.toList());
          dateByPath.forEach((relPath, date) {
            final content = contents[relPath];
            if (content != null) addValidEvents(date, content);
          });
        }
      }

      final now = DateTime.now();
      int removedCount = 0;

      for (final notification in pending) {
        final payload = notification.payload ?? '';
        if (!payload.startsWith('event_')) continue;

        final parts = payload.split('_');
        if (parts.length < 3) {
          await cancelNotification(notification.id);
          removedCount++;
          continue;
        }

        final date = parts[1];
        final notificationId = int.tryParse(parts[2]);

        // Remove notifications for past dates
        if (date.length == 8) {
          try {
            final year = int.parse(date.substring(0, 4));
            final month = int.parse(date.substring(4, 6));
            final day = int.parse(date.substring(6, 8));
            final eventDate = DateTime(year, month, day);
            if (eventDate.add(const Duration(hours: 25)).isBefore(now)) {
              await cancelNotification(notification.id);
              removedCount++;
              continue;
            }
          } catch (_) {}
        }

        // Remove if date file no longer exists
        if (!validEventsByDate.containsKey(date)) {
          await cancelNotification(notification.id);
          removedCount++;
          continue;
        }

        // Remove if event no longer exists in file
        if (notificationId != null) {
          final validEvents = validEventsByDate[date];
          if (validEvents == null || !validEvents.contains(notificationId)) {
            await cancelNotification(notification.id);
            removedCount++;
            continue;
          }
        }
      }

      if (removedCount > 0) {
        Log.i('NotificationService: removed $removedCount stale notifications');
      }
    } catch (e) {
      Log.e('NotificationService: error reviewing notifications', error: e);
    }
  }
}
