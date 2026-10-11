import 'package:planetxt/models/calendar_event.dart';
import 'package:planetxt/utils/markdown_parser.dart';

/// A todo of the week, with the day (`yyyyMMdd`) it is written in.
typedef DatedTask = ({String date, TaskItem task});

/// What a week (Monday to Sunday) holds.
class WeekReview {
  final DateTime monday;

  /// Checked todos, day by day.
  final List<DatedTask> done;

  /// Todos still unchecked, each text once, on the last day it appears.
  final List<DatedTask> open;

  /// Todos written on several days of the week (carried over, or copied),
  /// with how many days, and whether the last one has it checked.
  final List<({String text, int days, bool done})> carried;

  final List<CalendarEvent> events;

  const WeekReview({
    required this.monday,
    required this.done,
    required this.open,
    required this.carried,
    required this.events,
  });

  /// The seven days of the week, as `yyyyMMdd`.
  List<String> get dates => [
        for (var i = 0; i < 7; i++)
          formatDate(DateTime(monday.year, monday.month, monday.day + i)),
      ];

  static String formatDate(DateTime d) => '${d.year}'
      '${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  /// The review of the week holding [day], from each day's parsed tasks and
  /// events.
  static WeekReview of(
    DateTime day, {
    required List<TaskItem> Function(String date) tasksOf,
    required List<CalendarEvent> Function(String date) eventsOf,
  }) {
    final monday = DateTime(day.year, day.month, day.day - (day.weekday - 1));
    final review =
        WeekReview(monday: monday, done: [], open: [], carried: [], events: []);

    final lastOpen = <String, DatedTask>{};
    final daysByText = <String, Set<String>>{};
    final lastStateByText = <String, bool>{};
    for (final date in review.dates) {
      for (final task in tasksOf(date)) {
        final key = task.text.toLowerCase();
        (daysByText[key] ??= {}).add(date);
        lastStateByText[key] = task.isCompleted;
        if (task.isCompleted) {
          review.done.add((date: date, task: task));
          lastOpen.remove(key);
        } else {
          lastOpen[key] = (date: date, task: task);
        }
      }
      review.events.addAll(eventsOf(date));
    }
    review.open.addAll(lastOpen.values);
    for (final entry in daysByText.entries) {
      if (entry.value.length < 2) continue;
      final text = [...review.done, ...review.open]
              .where((t) => t.task.text.toLowerCase() == entry.key)
              .firstOrNull
              ?.task
              .text ??
          entry.key;
      review.carried.add((
        text: text,
        days: entry.value.length,
        done: lastStateByText[entry.key]!,
      ));
    }
    review.carried.sort((a, b) => b.days.compareTo(a.days));
    return review;
  }
}
