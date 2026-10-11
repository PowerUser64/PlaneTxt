import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:planetxt/providers/daily_file_provider.dart';
import 'package:planetxt/utils/week_review.dart';
import 'package:provider/provider.dart';

/// The week at a glance: what got done, what is still open, what keeps
/// being carried over, and the events. A day opens in the calendar.
class WeekReviewScreen extends StatefulWidget {
  /// Any day of the week to show first.
  final DateTime day;

  const WeekReviewScreen({super.key, required this.day});

  @override
  State<WeekReviewScreen> createState() => _WeekReviewScreenState();
}

class _WeekReviewScreenState extends State<WeekReviewScreen> {
  late DateTime _day = widget.day;

  void _moveWeek(int weeks) => setState(
      () => _day = DateTime(_day.year, _day.month, _day.day + 7 * weeks));

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DailyFileProvider>();
    final review = WeekReview.of(_day,
        tasksOf: provider.getTasks, eventsOf: provider.getCalendarEvents);
    final sunday = DateTime(
        review.monday.year, review.monday.month, review.monday.day + 6);
    final range = '${DateFormat('d MMM').format(review.monday)} to '
        '${DateFormat('d MMM yyyy').format(sunday)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Week review'),
        actions: [
          IconButton(
            onPressed: () => _moveWeek(-1),
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous week',
          ),
          IconButton(
            onPressed: () => _moveWeek(1),
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next week',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(range, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '${review.done.length} done, ${review.open.length} still open, '
            '${review.events.length} event(s)',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (review.carried.isNotEmpty)
            _Section(
              title: 'Carried over',
              icon: Icons.redo,
              children: [
                for (final c in review.carried)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(c.done
                        ? Icons.check_box
                        : Icons.check_box_outline_blank),
                    title: Text(c.text),
                    subtitle: Text('on ${c.days} days'),
                  ),
              ],
            ),
          if (review.open.isNotEmpty)
            _Section(
              title: 'Still open',
              icon: Icons.check_box_outline_blank,
              children: [
                for (final t in review.open)
                  _taskTile(context, t.date, t.task.text),
              ],
            ),
          if (review.done.isNotEmpty)
            _Section(
              title: 'Done',
              icon: Icons.check_box,
              children: [
                for (final t in review.done)
                  _taskTile(context, t.date, t.task.text),
              ],
            ),
          if (review.events.isNotEmpty)
            _Section(
              title: 'Events',
              icon: Icons.event,
              children: [
                for (final e in review.events)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.displayTitle),
                    subtitle: Text(
                        DateFormat('EEE d MMM, HH:mm').format(e.time)),
                    onTap: () => _openDay(context, e.date),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _taskTile(BuildContext context, String date, String text) =>
      ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(text),
        subtitle: Text(DateFormat('EEE d MMM').format(_parse(date))),
        onTap: () => _openDay(context, date),
      );

  /// Show [date] in the calendar, which follows the selected date.
  void _openDay(BuildContext context, String date) {
    context.read<DailyFileProvider>().setSelectedDate(date);
    Navigator.of(context).pop();
  }

  static DateTime _parse(String date) => DateTime(
        int.parse(date.substring(0, 4)),
        int.parse(date.substring(4, 6)),
        int.parse(date.substring(6, 8)),
      );
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.primary)),
            ],
          ),
          ...children,
        ],
      ),
    );
  }
}
