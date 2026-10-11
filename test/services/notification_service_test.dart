import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/constants/app_constants.dart';
import 'package:planetxt/services/notification_service.dart';
import 'package:planetxt/services/shared_prefs_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final event = DateTime(2026, 10, 11, 15, 0);
  final now = DateTime(2026, 10, 11, 14, 40);

  group('NotificationService.reminderTime', () {
    test('fires the chosen delay before the event', () {
      expect(NotificationService.reminderTime(event, 10, now),
          DateTime(2026, 10, 11, 14, 50));
      expect(NotificationService.reminderTime(event, 0, now), event);
    });

    test('skips a reminder whose time has passed, or when off', () {
      expect(NotificationService.reminderTime(event, 60, now), isNull);
      expect(NotificationService.reminderTime(event, null, now), isNull);
    });
  });

  group('NotificationService.reminderMinutes', () {
    Future<void> prefs(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      SharedPrefsService.useForTesting(await SharedPreferences.getInstance());
    }

    test('defaults to one hour', () async {
      await prefs({});
      expect(NotificationService().reminderMinutes, 60);
    });

    test('reads the chosen delay, a negative one meaning off', () async {
      await prefs({AppConstants.reminderMinutesKey: 10});
      expect(NotificationService().reminderMinutes, 10);
      await prefs({AppConstants.reminderMinutesKey: -1});
      expect(NotificationService().reminderMinutes, isNull);
    });
  });

  test('a tapped reminder points to its day', () {
    expect(NotificationService.dateFromPayload('event_20261011_123'),
        '20261011');
    expect(NotificationService.dateFromPayload('test'), isNull);
    expect(NotificationService.dateFromPayload(null), isNull);
  });
}
