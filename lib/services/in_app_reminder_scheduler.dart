import 'dart:async';

import 'package:flutter/foundation.dart';

/// A reminder waiting in an [InAppReminderScheduler].
class InAppReminder {
  final int id;
  final DateTime fireAt;
  final DateTime eventTime;
  final String title;
  final String body;
  final String payload;

  const InAppReminder({
    required this.id,
    required this.fireAt,
    required this.eventTime,
    required this.title,
    required this.body,
    required this.payload,
  });
}

/// Fires reminders from inside the app, for platforms whose notification
/// plugin cannot schedule (Linux): they only fire while the app runs.
/// The wall clock is checked at an interval rather than trusting one long
/// timer, which would fire late after the computer slept.
class InAppReminderScheduler {
  InAppReminderScheduler({
    required this.onFire,
    DateTime Function()? clock,
    this.checkInterval = const Duration(seconds: 20),
  }) : _clock = clock ?? DateTime.now;

  final void Function(InAppReminder reminder) onFire;
  final DateTime Function() _clock;
  final Duration checkInterval;
  final Map<int, InAppReminder> _reminders = {};
  Timer? _ticker;

  List<InAppReminder> get pending => List.unmodifiable(_reminders.values);

  /// Add [reminder], replacing any with the same id.
  void schedule(InAppReminder reminder) {
    _reminders[reminder.id] = reminder;
    _ticker ??= Timer.periodic(checkInterval, (_) => check());
  }

  void cancel(int id) {
    _reminders.remove(id);
    _stopIfIdle();
  }

  void cancelAll() {
    _reminders.clear();
    _stopIfIdle();
  }

  /// Fire the reminders now due. One whose event has already started (the
  /// computer slept through its time) is dropped instead.
  @visibleForTesting
  void check() {
    final now = _clock();
    final due =
        _reminders.values.where((r) => !r.fireAt.isAfter(now)).toList();
    for (final reminder in due) {
      _reminders.remove(reminder.id);
      if (reminder.eventTime.isAfter(now)) onFire(reminder);
    }
    _stopIfIdle();
  }

  void _stopIfIdle() {
    if (_reminders.isNotEmpty) return;
    _ticker?.cancel();
    _ticker = null;
  }
}
