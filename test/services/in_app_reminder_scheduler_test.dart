import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/services/in_app_reminder_scheduler.dart';

void main() {
  late DateTime now;
  late List<int> fired;
  late InAppReminderScheduler scheduler;

  final event = DateTime(2026, 10, 11, 15, 0);

  InAppReminder reminder(int id, {DateTime? eventTime}) {
    final time = eventTime ?? event;
    return InAppReminder(
      id: id,
      fireAt: time.subtract(const Duration(hours: 1)),
      eventTime: time,
      title: '15:00 - Dentist',
      body: '',
      payload: 'event_20261011_$id',
    );
  }

  setUp(() {
    now = DateTime(2026, 10, 11, 13, 0);
    fired = [];
    scheduler = InAppReminderScheduler(
      onFire: (r) => fired.add(r.id),
      clock: () => now,
    );
  });

  tearDown(() => scheduler.cancelAll());

  test('fires a reminder once it is due, and only once', () {
    scheduler.schedule(reminder(1));

    scheduler.check();
    expect(fired, isEmpty);

    now = DateTime(2026, 10, 11, 14, 0);
    scheduler.check();
    scheduler.check();
    expect(fired, [1]);
    expect(scheduler.pending, isEmpty);
  });

  test('drops a reminder whose event started while asleep', () {
    scheduler.schedule(reminder(1));

    now = DateTime(2026, 10, 11, 16, 0); // woke up after the event
    scheduler.check();

    expect(fired, isEmpty);
    expect(scheduler.pending, isEmpty);
  });

  test('a replaced reminder fires once, a cancelled one never', () {
    scheduler
      ..schedule(reminder(1))
      ..schedule(reminder(1))
      ..schedule(reminder(2))
      ..cancel(2);
    expect(scheduler.pending.map((r) => r.id), [1]);

    now = DateTime(2026, 10, 11, 14, 30);
    scheduler.check();

    expect(fired, [1]);
  });

  test('checks the clock periodically on its own', () async {
    final ticking = InAppReminderScheduler(
      onFire: (r) => fired.add(r.id),
      clock: () => now,
      checkInterval: const Duration(milliseconds: 10),
    )..schedule(reminder(1));

    now = DateTime(2026, 10, 11, 14, 0, 30);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(fired, [1]);
    expect(ticking.pending, isEmpty);
  });
}
